/* file: df_train_dense_default_impl.i */
/*******************************************************************************
* Copyright 2014-2017 Intel Corporation
* All Rights Reserved.
*
* If this  software was obtained  under the  Intel Simplified  Software License,
* the following terms apply:
*
* The source code,  information  and material  ("Material") contained  herein is
* owned by Intel Corporation or its  suppliers or licensors,  and  title to such
* Material remains with Intel  Corporation or its  suppliers or  licensors.  The
* Material  contains  proprietary  information  of  Intel or  its suppliers  and
* licensors.  The Material is protected by  worldwide copyright  laws and treaty
* provisions.  No part  of  the  Material   may  be  used,  copied,  reproduced,
* modified, published,  uploaded, posted, transmitted,  distributed or disclosed
* in any way without Intel's prior express written permission.  No license under
* any patent,  copyright or other  intellectual property rights  in the Material
* is granted to  or  conferred  upon  you,  either   expressly,  by implication,
* inducement,  estoppel  or  otherwise.  Any  license   under such  intellectual
* property rights must be express and approved by Intel in writing.
*
* Unless otherwise agreed by Intel in writing,  you may not remove or alter this
* notice or  any  other  notice   embedded  in  Materials  by  Intel  or Intel's
* suppliers or licensors in any way.
*
*
* If this  software  was obtained  under the  Apache License,  Version  2.0 (the
* "License"), the following terms apply:
*
* You may  not use this  file except  in compliance  with  the License.  You may
* obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
*
*
* Unless  required  by   applicable  law  or  agreed  to  in  writing,  software
* distributed under the License  is distributed  on an  "AS IS"  BASIS,  WITHOUT
* WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
*
* See the   License  for the   specific  language   governing   permissions  and
* limitations under the License.
*******************************************************************************/

/*
//++
//  Implementation of auxiliary functions for decision forest train algorithms
//  (defaultDense) method.
//--
*/

#ifndef __DF_TRAIN_DENSE_DEFAULT_IMPL_I__
#define __DF_TRAIN_DENSE_DEFAULT_IMPL_I__

#include "dtrees_train_data_helper.i"
#include "threading.h"
#include "dtrees_model_impl.h"

using namespace daal::algorithms::dtrees::training::internal;

namespace daal
{
namespace algorithms
{
namespace decision_forest
{
namespace training
{
namespace internal
{

//////////////////////////////////////////////////////////////////////////////////////////
// Service structure, contains numeric tables to be calculated as result
//////////////////////////////////////////////////////////////////////////////////////////
struct ResultData
{
public:
    ResultData(const Parameter& par, NumericTable* _varImp, NumericTable* _oobError) :
        oobError(nullptr), varImp(nullptr)
    {
        if(par.varImportance != decision_forest::training::none)
            varImp = _varImp;
        if(par.resultsToCompute & decision_forest::training::computeOutOfBagError)
            oobError = _oobError;
    }
    NumericTable* varImp; //if needed then allocated outside kernel
    NumericTable* oobError; //if needed then allocated outside kernel
    NumericTablePtr oobIndicesNum; //if needed then allocated in kernel
    NumericTablePtr oobIndices; //if needed then allocated in kernel
};

//////////////////////////////////////////////////////////////////////////////////////////
// Service structure, contains workset required for tree calculation in one thread
//////////////////////////////////////////////////////////////////////////////////////////
template <typename algorithmFPType, CpuType cpu>
class TreeThreadCtxBase
{
public:
    TreeThreadCtxBase(algorithmFPType* _varImp = nullptr) : varImp(_varImp), varImpVariance(nullptr), nTrees(0), oobBuf(nullptr){}
    ~TreeThreadCtxBase()
    {
        if(varImpVariance)
            service_free<algorithmFPType, cpu>(varImpVariance);
        if(oobBuf)
            service_free<byte, cpu>(oobBuf);
    }
    void finalizeVarImp(size_t nVars, training::VariableImportanceMode mode);

protected:
    bool init(const Parameter& par, const NumericTable* x)
    {
        if(par.varImportance == training::MDA_Scaled)
        {
            varImpVariance = service_calloc<algorithmFPType, cpu>(x->getNumberOfColumns());
            if(!varImpVariance)
                return false;
        }
        return true;
    }

    void reduceTo(TreeThreadCtxBase& other, size_t nVars, size_t nSamples) const
    {
        // Reduces tls variable importance results
        if(varImp)
        {
            for(size_t i = 0; i < nVars; ++i)
                other.varImp[i] += varImp[i];
        }
        if(varImpVariance)
        {
            for(size_t i = 0; i < nVars; ++i)
                other.varImpVariance[i] += varImpVariance[i];
        }
        other.nTrees += nTrees;
    }

public:
    algorithmFPType* varImp;
    algorithmFPType* varImpVariance;
    size_t nTrees;
    byte* oobBuf;
};

//////////////////////////////////////////////////////////////////////////////////////////
// Finalizes calculation of variable importance results
//////////////////////////////////////////////////////////////////////////////////////////
template <typename algorithmFPType, CpuType cpu>
void TreeThreadCtxBase<algorithmFPType, cpu>::finalizeVarImp(size_t nVars, training::VariableImportanceMode mode)
{
    const algorithmFPType div = 1. / algorithmFPType(nTrees);
    if(mode == training::MDA_Scaled)
    {
        //average over all trees and scale by its variance
        for(size_t i = 0; i < nVars; ++i)
        {
            varImp[i] *= div;
            varImpVariance[i] = varImpVariance[i] * div - varImp[i] * varImp[i];
            if(isPositive<algorithmFPType, cpu>(varImpVariance[i]))
                varImp[i] /= daal::internal::Math<algorithmFPType, cpu>::sSqrt(varImpVariance[i] * div);
        }
    }
    else
    {
        //average over all trees
        for(size_t i = 0; i < nVars; ++i)
            varImp[i] *= div;
    }

#if ENABLE_VAR_IMP_NORMALIZATION
    algorithmFPType sum = 0;
    for(size_t i = 0; i < nVars; ++i)
        sum += varImp[i];
    //normalize by division to the sum of all values
    if(!isPositive<algorithmFPType, cpu>(sum))
    {
        algorithmFPType maxVal = 0;
        for(size_t i = 0; i < nVars; ++i)
        {
            const algorithmFPType val = daal::internal::Math<algorithmFPType, cpu>::sFabs(varImp[i]);
            maxVal = daal::internal::Math<algorithmFPType, cpu>::sMax(maxVal, val);
        }
        if(!isPositive<algorithmFPType, cpu>(maxVal))
            return;
        const algorithmFPType div = 1. / maxVal;
        for(size_t i = 0; i < nVars; varImp[i++] *= div);
    }
    else
    {
        sum = 1. / sum;
        for(size_t i = 0; i < nVars; varImp[i++] *= sum);
    }
#endif
}

template <typename algorithmFPType, CpuType cpu, class Ctx>
Ctx* createTlsContext(const NumericTable *x, const Parameter& par, size_t nClasses)
{
    const size_t szVarImp = (par.varImportance == decision_forest::training::none ? 0 : x->getNumberOfColumns()*sizeof(algorithmFPType));
    size_t szCtx = sizeof(Ctx);
    if(szCtx%sizeof(algorithmFPType))
        szCtx = sizeof(algorithmFPType)*(1 + (szCtx / sizeof(algorithmFPType)));
    const size_t sz = szCtx + szVarImp;
    byte* ptr = service_scalable_calloc<byte, cpu>(sz);
    Ctx* ctx = new (ptr)Ctx();
    if(ctx)
    {
        if(szVarImp)
            ctx->varImp = (algorithmFPType*)(ptr + szCtx);
        if(!ctx->init(par, x, nClasses))
        {
            //allocation of extra data hasn't succeeded
            ctx->~Ctx();
            service_scalable_free<byte, cpu>(ptr);
            return nullptr;
        }
    }
    return ctx;
}

//////////////////////////////////////////////////////////////////////////////////////////
// compute() implementation
//////////////////////////////////////////////////////////////////////////////////////////
template <typename algorithmFPType, CpuType cpu, typename ModelType, typename TaskType>
services::Status computeImpl(const NumericTable *x, const NumericTable *y, ModelType& md, ResultData& res,
    const Parameter& par, size_t nClasses)
{
    DAAL_CHECK(md.resize(par.nTrees), ErrorMemoryAllocationFailed);
    dtrees::internal::FeatureTypeHelper<cpu> featHelper;
    DAAL_CHECK(featHelper.init(x), ErrorMemoryAllocationFailed);

    dtrees::internal::SortedFeaturesHelper sortedFeatHelper;
    services::Status s;
    if(!par.memorySavingMode)
    {
        s = sortedFeatHelper.init<algorithmFPType, cpu>(*x);
        if(!s)
            return s;
    }

    const auto nFeatures = x->getNumberOfColumns();
    WriteOnlyRows<algorithmFPType, cpu> varImpBD(res.varImp, 0, 1);
    if(res.varImp)
        DAAL_CHECK_BLOCK_STATUS(varImpBD);

    //set of auxiliary data used by single thread or a target for reduction by multiple threads
    typedef typename TaskType::ThreadCtxType Ctx;
    Ctx mainCtx(varImpBD.get());
    DAAL_CHECK(mainCtx.init(par, x, nClasses), ErrorMemoryAllocationFailed);

    if(mainCtx.varImp)
        //initialize its data
        daal::services::internal::service_memset<algorithmFPType, cpu>(mainCtx.varImp, 0, nFeatures);

    //use tls in case of multiple threads
    const bool bThreaded = (threader_get_max_threads_number() > 1) && (par.nTrees > 1);
    daal::tls<Ctx*> tlsCtx([&]()->Ctx*
    {
        //in case of single thread no need to allocate
        return (bThreaded ? createTlsContext<algorithmFPType, cpu, Ctx>(x, par, nClasses) : &mainCtx);
    });
    daal::tls<TaskType*> tlsTask([&]()->TaskType*
    {
        //in case of single thread no need to allocate
        Ctx* ctx = tlsCtx.local();
        return ctx ? new TaskType(x, y, par, featHelper, par.memorySavingMode ? nullptr : &sortedFeatHelper, *ctx, nClasses) : nullptr;
    });

    bool bMemoryAllocationFailed = false;
    daal::threader_for(par.nTrees, par.nTrees, [&](size_t i)
    {
        TaskType* task = tlsTask.local();
        if(!task)
        {
            bMemoryAllocationFailed = true;
            return;
        }
        dtrees::internal::Tree* pTree = task->run(size_t(par.seed)*(i + 1));
        if(pTree)
            md.add((typename ModelType::TreeType&)*pTree);
    });
    tlsCtx.reduce([&](Ctx* ctx)-> void
    {
        if(ctx && bThreaded)
        {
            ctx->reduceTo(mainCtx, nFeatures, x->getNumberOfRows());
            ctx->~Ctx();
            service_scalable_free<byte, cpu>((byte*)ctx);
        }
    });
    tlsTask.parallel_reduce([&](TaskType* task)-> void
    {
        delete task;
    });
    DAAL_CHECK_MALLOC(md.size() == par.nTrees);
    DAAL_CHECK_MALLOC(!bMemoryAllocationFailed);

    //finalize results computation
    //variable importance
    if(varImpBD.get())
        mainCtx.finalizeVarImp(nFeatures, par.varImportance);

    //OOB error
    if(par.resultsToCompute & computeOutOfBagError)
    {
        WriteOnlyRows<algorithmFPType, cpu> oobErr(res.oobError, 0, 1);
        s = mainCtx.finalizeOOBError(y, *oobErr.get());
    }
    return s;
}

//////////////////////////////////////////////////////////////////////////////////////////
// Base task class. Implements general pipeline of tree building
//////////////////////////////////////////////////////////////////////////////////////////
template <typename algorithmFPType, typename DataHelper, CpuType cpu>
class TrainBatchTaskBase
{
public:
    typedef TreeThreadCtxBase<algorithmFPType, cpu> ThreadCtxType;
    dtrees::internal::Tree* run(size_t seed);

protected:
    typedef dtrees::internal::TVector<algorithmFPType, cpu, DefaultAllocator<cpu>> algorithmFPTypeArray;
    typedef dtrees::internal::TVector<IndexType, cpu, DefaultAllocator<cpu>> IndexTypeArray;
    TrainBatchTaskBase(const NumericTable *x, const NumericTable *y, const Parameter& par,
        const dtrees::internal::FeatureTypeHelper<cpu>& featHelper,
        const dtrees::internal::SortedFeaturesHelper* sortedFeatHelper,
        ThreadCtxType& threadCtx, size_t nClasses):
        _data(x), _resp(y), _par(par), _brng(nullptr), _nClasses(nClasses),
        _nSamples(par.observationsPerTreeFraction*x->getNumberOfRows()),
        _nFeaturesPerNode(par.featuresPerNode),
        _helper(sortedFeatHelper, nClasses),
        _impurityThreshold(_par.impurityThreshold),
        _nFeatureBufs(1), //for sequential processing
        _featHelper(featHelper),
        _threadCtx(threadCtx),
        _accuracy(daal::data_feature_utils::internal::EpsilonVal<algorithmFPType, cpu>::get())
    {
        if(_impurityThreshold < _accuracy)
            _impurityThreshold = _accuracy;
    }
    ~TrainBatchTaskBase()
    {
        delete _brng;
    }

    size_t nFeatures() const { return _data->getNumberOfColumns(); }
    typename DataHelper::NodeType::Base* build(size_t iStart, size_t n, size_t level,
        typename DataHelper::ImpurityData& curImpurity, bool& bUnorderedFeaturesUsed);
    algorithmFPType* featureBuf(size_t iBuf) const { DAAL_ASSERT(iBuf < _nFeatureBufs); return _aFeatureBuf[iBuf].get(); }
    IndexType* featureIndexBuf(size_t iBuf) const { DAAL_ASSERT(iBuf < _nFeatureBufs); return _aFeatureIndexBuf[iBuf].get(); }
    bool terminateCriteria(size_t nSamples, size_t level, typename DataHelper::ImpurityData& imp) const
    {
        return (nSamples < 2 * _par.minObservationsInLeafNode ||
            _helper.terminateCriteria(imp, _impurityThreshold, nSamples) ||
            ((_par.maxTreeDepth > 0) && (level >= _par.maxTreeDepth)));
    }
    ThreadCtxType& threadCtx() { return _threadCtx; }
    typename DataHelper::NodeType::Split* makeSplit(size_t iFeature, algorithmFPType featureValue, bool bUnordered,
        typename DataHelper::NodeType::Base* left, typename DataHelper::NodeType::Base* right, algorithmFPType imp);
    typename DataHelper::NodeType::Leaf* makeLeaf(const IndexType* idx, size_t n, typename DataHelper::ImpurityData& imp);

    bool findBestSplit(size_t iStart, size_t n, const typename DataHelper::ImpurityData& curImpurity,
        IndexType& iBestFeature, typename DataHelper::TSplitData& split);
    bool findBestSplitSerial(size_t iStart, size_t n, const typename DataHelper::ImpurityData& curImpurity,
        IndexType& iBestFeature, typename DataHelper::TSplitData& split);
    bool findBestSplitThreaded(size_t iStart, size_t n, const typename DataHelper::ImpurityData& curImpurity,
        IndexType& iBestFeature, typename DataHelper::TSplitData& split);
    bool simpleSplit(size_t iStart, const typename DataHelper::ImpurityData& curImpurity,
        IndexType& iFeatureBest, typename DataHelper::TSplitData& split);
    void addImpurityDecrease(IndexType iFeature, size_t n, const typename DataHelper::ImpurityData& curImpurity,
        const typename DataHelper::TSplitData& split);

    void featureValuesToBuf(size_t iFeature, algorithmFPType* featureVal, IndexType* aIdx, size_t n)
    {
        _helper.getColumnValues(iFeature, aIdx, n, featureVal);
        daal::algorithms::internal::qSort<algorithmFPType, int, cpu>(n, featureVal, aIdx);
    }

    //find features to check in the current split node
    void chooseFeatures()
    {
        const size_t n = nFeatures();
        if(n == _nFeaturesPerNode)
        {
            for(size_t i = 0; i < n; ++i)
                _aFeatureIdx[i] = i;
        }
        else
        {
            RNGs<IndexType, cpu> rng;
            rng.uniformWithoutReplacement(_nFeaturesPerNode, _aFeatureIdx.get(), _aFeatureIdx.get() + _nFeaturesPerNode, *_brng, 0, n);
        }
    }

    bool computeResults(const dtrees::internal::Tree& t);

    algorithmFPType computeOOBError(const dtrees::internal::Tree& t, size_t n, const IndexType* aInd);

    algorithmFPType computeOOBErrorPerm(const dtrees::internal::Tree& t,
        size_t n, const IndexType* aInd, const IndexType* aPerm, size_t iPermutedFeature);

protected:
    BaseRNGs<cpu>* _brng;
    const NumericTable *_data;
    const NumericTable *_resp;
    const Parameter& _par;
    const size_t _nSamples;
    const size_t _nFeaturesPerNode;
    const size_t _nFeatureBufs; //number of buffers to get feature values (to process features independently in parallel)
    mutable TVector<IndexType, cpu, DefaultAllocator<cpu>> _aSample;
    mutable TArray<algorithmFPTypeArray, cpu> _aFeatureBuf;
    mutable TArray<IndexTypeArray, cpu> _aFeatureIndexBuf;

    TArray<IndexType, cpu> _aFeatureIdx; //indices of features to be used for the soplit at the current level
    DataHelper _helper;
    typename DataHelper::TreeType _tree;
    const FeatureTypeHelper<cpu>& _featHelper;
    algorithmFPType _accuracy;
    algorithmFPType _impurityThreshold;
    ThreadCtxType& _threadCtx;
    size_t _nClasses;
};

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
dtrees::internal::Tree* TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::run(size_t seed)
{
    if(_brng)
    {
        delete _brng;
        _brng = nullptr;
    }
    _brng = new BaseRNGs<cpu>(seed);
    _tree.destroy();
    _aSample.reset(_nSamples);
    _aFeatureBuf.reset(_nFeatureBufs);
    _aFeatureIndexBuf.reset(_nFeatureBufs);
    _aFeatureIdx.reset(_nFeaturesPerNode * 2); // _nFeaturesPerNode elements are used by algorithm, others are used internally by generator

    if(!_aSample.get() || !_helper.reset(_nSamples) || !_aFeatureBuf.get() || !_aFeatureIndexBuf.get() || !_aFeatureIdx.get())
        return nullptr;

    //allocate temporary bufs
    for(size_t i = 0; i < _nFeatureBufs; ++i)
    {
        _aFeatureBuf[i].reset(_nSamples);
        if(!_aFeatureBuf[i].get())
            return nullptr;
        _aFeatureIndexBuf[i].reset(_nSamples);
        if(!_aFeatureIndexBuf[i].get())
            return nullptr;
    }

    if(_par.bootstrap)
    {
        RNGs<int, cpu> rng;
        rng.uniform(_nSamples, _aSample.get(), *_brng, 0, _data->getNumberOfRows());
        daal::algorithms::internal::qSort<int, cpu>(_nSamples, _aSample.get());
    }
    else
    {
        auto aSample = _aSample.get();
        for(size_t i = 0; i < _nSamples; ++i)
            aSample[i] = i;
    }
    //init responses buffer, keep _aSample values in it
    if(!_helper.init(_data, _resp, _aSample.get()))
        return nullptr;

    //use _aSample as an array of response indices stored by helper from now on
    for(size_t i = 0; i < _aSample.size(); _aSample[i] = i, ++i);

    typename DataHelper::ImpurityData initialImpurity;
    _helper.calcImpurity(_aSample.get(), _nSamples, initialImpurity);
    bool bUnorderedFeaturesUsed = false;
    typename DataHelper::NodeType::Base* nd = build(0, _nSamples, 0, initialImpurity, bUnorderedFeaturesUsed);
    if(!nd)
        return nullptr;
    _tree.reset(nd, bUnorderedFeaturesUsed);
    _threadCtx.nTrees++;
    if((_par.resultsToCompute & computeOutOfBagError) || (_par.varImportance > MDI))
    {
        if(!computeResults(_tree))
            return nullptr;
    }
    return &_tree;
}

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
typename DataHelper::NodeType::Split* TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::makeSplit(size_t iFeature,
    algorithmFPType featureValue, bool bUnordered,
    typename DataHelper::NodeType::Base* left, typename DataHelper::NodeType::Base* right, algorithmFPType imp)
{
    typename DataHelper::NodeType::Split* pNode = _tree.allocator().allocSplit();
    pNode->set(iFeature, featureValue, bUnordered);
    pNode->kid[0] = left;
    pNode->kid[1] = right;
#ifdef DEBUG_CHECK_IMPURITY
    pNode->impurity = imp;
#endif
    return pNode;
}

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
typename DataHelper::NodeType::Leaf* TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::makeLeaf(const IndexType* idx,
    size_t n, typename DataHelper::ImpurityData& imp)
{
    typename DataHelper::NodeType::Leaf* pNode = _tree.allocator().allocLeaf();
    _helper.setLeafData(*pNode, idx, n, imp);
    return pNode;
}

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
typename DataHelper::NodeType::Base* TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::build(size_t iStart, size_t n,
    size_t level, typename DataHelper::ImpurityData& curImpurity, bool& bUnorderedFeaturesUsed)
{
    if(terminateCriteria(n, level, curImpurity))
        return makeLeaf(_aSample.get() + iStart, n, curImpurity);

    typename DataHelper::TSplitData split;
    IndexType iFeature;
    if(findBestSplit(iStart, n, curImpurity, iFeature, split))
    {
        if(_par.varImportance == training::MDI)
            addImpurityDecrease(iFeature, n, curImpurity, split);
        typename DataHelper::NodeType::Base* left = build(iStart, split.nLeft, level + 1, split.left, bUnorderedFeaturesUsed);
        const size_t nLeft = split.nLeft;
        _helper.convertLeftImpToRight(n, curImpurity, split);
        typename DataHelper::NodeType::Base* right = build(iStart + nLeft, split.nLeft, level + 1, split.left, bUnorderedFeaturesUsed);
        typename DataHelper::NodeType::Base* res = nullptr;
        if(!left || !right || !(res = makeSplit(iFeature, split.featureValue, split.featureUnordered, left, right, curImpurity.var)))
        {
            if(left)
                dtrees::internal::deleteNode<typename DataHelper::NodeType, typename DataHelper::TreeType::Allocator>(left, _tree.allocator());
            if(right)
                dtrees::internal::deleteNode<typename DataHelper::NodeType, typename DataHelper::TreeType::Allocator>(right, _tree.allocator());
            return nullptr;
        }
        bUnorderedFeaturesUsed |= split.featureUnordered;
#ifdef DEBUG_CHECK_IMPURITY
        res->count = n;
        DAAL_ASSERT(nLeft == left->count);
        DAAL_ASSERT(split.nLeft == right->count);
#endif
        return res;
    }
    return makeLeaf(_aSample.get() + iStart, n, curImpurity);
}

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
bool TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::simpleSplit(size_t iStart,
    const typename DataHelper::ImpurityData& curImpurity, IndexType& iFeatureBest, typename DataHelper::TSplitData& split)
{
    RNGs<IndexType, cpu> rng;
    algorithmFPType featBuf[2];
    IndexType* aIdx = _aSample.get() + iStart;
    for(size_t i = 0; i < _nFeaturesPerNode; ++i)
    {
        IndexType iFeature;
        rng.uniform(1, &iFeature, *_brng, 0, _data->getNumberOfColumns());
        featureValuesToBuf(iFeature, featBuf, aIdx, 2);
        if(featBuf[1] - featBuf[0] <= _accuracy) //all values of the feature are the same
            continue;
        _helper.simpleSplit(featBuf, aIdx, split);
        split.impurityDecrease = curImpurity.var;
        iFeatureBest = iFeature;
        return true;
    }
    return false;
}

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
bool TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::findBestSplit(size_t iStart, size_t n,
    const typename DataHelper::ImpurityData& curImpurity, IndexType& iFeatureBest, typename DataHelper::TSplitData& split)
{
    if(n == 2)
    {
        DAAL_ASSERT(_par.minObservationsInLeafNode == 1);
#ifdef DEBUG_CHECK_IMPURITY
        _helper.checkImpurity(_aSample.get() + iStart, n, curImpurity);
#endif
        return simpleSplit(iStart, curImpurity, iFeatureBest, split);
    }
    if(_nFeatureBufs == 1)
        return findBestSplitSerial(iStart, n, curImpurity, iFeatureBest, split);
    return findBestSplitThreaded(iStart, n, curImpurity, iFeatureBest, split);
}

//find best split and put it to featureIndexBuf
template <typename algorithmFPType, typename DataHelper, CpuType cpu>
bool TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::findBestSplitSerial(size_t iStart, size_t n,
    const typename DataHelper::ImpurityData& curImpurity, IndexType& iBestFeature,
    typename DataHelper::TSplitData& bestSplit)
{
    chooseFeatures();
    const float qMax = 0.02; //min fracture of observations to be handled as indexed feature values
    IndexType* bestSplitIdx = featureIndexBuf(0) + iStart;
    IndexType* aIdx = _aSample.get() + iStart;
    int iBestSplit = -1;
    int idxFeatureValueBestSplit = -1; //when sorted feature is used
    typename DataHelper::TSplitData split;
    const float fact = float(n);
    for(size_t i = 0; i < _nFeaturesPerNode; ++i)
    {
        const auto iFeature = _aFeatureIdx[i];
        const bool bUseSortedFeatures = (!_par.memorySavingMode) &&
            (fact > qMax*float(_helper.sortedFeatures().getMaxNumberOfDiffValues(iFeature)));

        if(bUseSortedFeatures)
        {
            if(!_helper.hasDiffFeatureValues(iFeature, aIdx, n))
                continue;//all values of the feature are the same
            split.featureUnordered = _featHelper.isUnordered(iFeature);
            //index of best feature value in the array of sorted feature values
            const int idxFeatureValue = _helper.findBestSplitForFeatureSorted(featureBuf(0), iFeature, aIdx, n,
                _par.minObservationsInLeafNode, curImpurity, split);
            if(idxFeatureValue < 0)
                continue;
            iBestSplit = i;
            split.copyTo(bestSplit);
            idxFeatureValueBestSplit = idxFeatureValue;
        }
        else
        {
            algorithmFPType* featBuf = featureBuf(0) + iStart; //single thread
            featureValuesToBuf(iFeature, featBuf, aIdx, n);
            if(featBuf[n - 1] - featBuf[0] <= _accuracy) //all values of the feature are the same
                continue;
#ifdef DEBUG_CHECK_IMPURITY
            _helper.checkImpurity(aIdx, n, curImpurity);
#endif
            split.featureUnordered = _featHelper.isUnordered(iFeature);
            if(!_helper.findBestSplitForFeature(featBuf, aIdx, n, _par.minObservationsInLeafNode, _accuracy, curImpurity, split))
                continue;
            idxFeatureValueBestSplit = -1;
            iBestSplit = i;
            split.copyTo(bestSplit);
            DAAL_ASSERT(bestSplit.iStart < n);
            DAAL_ASSERT(bestSplit.iStart + bestSplit.nLeft <= n);
            if(i + 1 < _nFeaturesPerNode || split.featureUnordered)
                tmemcpy<IndexType, cpu>(bestSplitIdx, aIdx, n);
#ifdef DEBUG_CHECK_IMPURITY
            _helper.checkImpurity(aIdx, bestSplit.nLeft, bestSplit.left);
#endif
        }
    }
    if(iBestSplit < 0)
        return false; //not found

    iBestFeature = _aFeatureIdx[iBestSplit];
    bool bCopyToIdx = true;
    if(idxFeatureValueBestSplit >= 0)
    {
        //sorted feature was used
        //calculate impurity and get split to bestSplitIdx
        _helper.finalizeBestSplit(aIdx, n, iBestFeature, idxFeatureValueBestSplit, bestSplit, bestSplitIdx);
    }
    else if(bestSplit.featureUnordered)
    {
        if(bestSplit.iStart)
        {
            DAAL_ASSERT(bestSplit.iStart + bestSplit.nLeft <= n);
            tmemcpy<IndexType, cpu>(aIdx, bestSplitIdx + bestSplit.iStart, bestSplit.nLeft);
            aIdx += bestSplit.nLeft;
            tmemcpy<IndexType, cpu>(aIdx, bestSplitIdx, bestSplit.iStart);
            aIdx += bestSplit.iStart;
            bestSplitIdx += bestSplit.iStart + bestSplit.nLeft;
            if(n > (bestSplit.iStart + bestSplit.nLeft))
                tmemcpy<IndexType, cpu>(aIdx, bestSplitIdx, n - bestSplit.iStart - bestSplit.nLeft);
            bCopyToIdx = false;//done
        }
    }
    else
        bCopyToIdx = (iBestSplit + 1 < _nFeaturesPerNode); //if iBestSplit is the last considered feature
                                                           //then aIdx already contains the best split, no need to copy
    if(bCopyToIdx)
        tmemcpy<IndexType, cpu>(aIdx, bestSplitIdx, n);
    return true;
}

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
bool TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::findBestSplitThreaded(size_t iStart, size_t n,
    const typename DataHelper::ImpurityData& curImpurity, IndexType& iFeatureBest, typename DataHelper::TSplitData& split)
{
    chooseFeatures();
    TArray<typename DataHelper::TSplitData, cpu> aFeatureSplit(_nFeaturesPerNode);
    //TODO, if parallel for features
    return false;
}

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
void TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::addImpurityDecrease(IndexType iFeature, size_t n,
    const typename DataHelper::ImpurityData& curImpurity,
    const typename DataHelper::TSplitData& split)
{
    DAAL_ASSERT(_threadCtx.varImp);
    if(!isZero<algorithmFPType, cpu>(split.impurityDecrease))
        _threadCtx.varImp[iFeature] += split.impurityDecrease;
}

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
bool TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::computeResults(const dtrees::internal::Tree& t)
{
    const size_t nOOB = _helper.getNumOOBIndices();
    TArray<IndexType, cpu> oobIndices(nOOB);
    if(!oobIndices.get())
        return false;
    _helper.getOOBIndices(oobIndices.get());
    const bool bMDA(_par.varImportance == training::MDA_Raw || _par.varImportance == training::MDA_Scaled);
    if(_par.resultsToCompute & computeOutOfBagError || bMDA)
    {
        const algorithmFPType oobError = computeOOBError(t, nOOB, oobIndices.get());
        if(bMDA)
        {
            TArray<IndexType, cpu> permutation(nOOB);
            if(!permutation.get())
                return false;
            for(size_t i = 0; i < nOOB; permutation[i] = i, ++i);

            for(size_t i = 0, n = nFeatures(); i < n; ++i)
            {
                shuffle<cpu>(_brng->getState(), nOOB, permutation.get());
                const algorithmFPType permOOBError = computeOOBErrorPerm(t, nOOB, oobIndices.get(), permutation.get(), i);
                const algorithmFPType diff = (permOOBError - oobError);
                _threadCtx.varImp[i] += diff;
                if(_threadCtx.varImpVariance)
                    _threadCtx.varImpVariance[i] += diff*diff;
            }
        }
    }
    return true;
}

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
algorithmFPType predictionError(const DataHelper& h, const dtrees::internal::Tree& t,
    const algorithmFPType* x, const NumericTable* resp, size_t iRow)
{
    ReadRows<algorithmFPType, cpu> y(const_cast<NumericTable*>(resp), iRow, 1);
    return h.predictionError(h.predict(t, x), *y.get());
}

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
algorithmFPType TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::computeOOBErrorPerm(const dtrees::internal::Tree& t,
    size_t n, const IndexType* aInd, const IndexType* aPerm, size_t iPermutedFeature)
{
    DAAL_ASSERT(n);

    const auto dim = nFeatures();

    //compute prediction error on each OOB row and get its mean using online formulae (Welford)
    //TODO: can be threader_for() block
    TArray<algorithmFPType, cpu> buf(dim);
    ReadRows<algorithmFPType, cpu> x(const_cast<NumericTable*>(_data), aInd[0], 1);
    tmemcpy<algorithmFPType, cpu>(buf.get(), x.get(), dim);
    ReadRows<algorithmFPType, cpu> p(const_cast<NumericTable*>(_data), aInd[aPerm[0]], 1);
    buf[iPermutedFeature] = p.get()[iPermutedFeature];
    algorithmFPType mean = predictionError<algorithmFPType, DataHelper, cpu>(_helper, t, buf.get(), _resp, aInd[0]);

    for(size_t i = 1; i < n; ++i)
    {
        tmemcpy<algorithmFPType, cpu>(buf.get(), x.set(const_cast<NumericTable*>(_data), aInd[i], 1), dim);
        buf[iPermutedFeature] = p.set(const_cast<NumericTable*>(_data), aInd[aPerm[i]], 1)[iPermutedFeature];
        algorithmFPType val = predictionError<algorithmFPType, DataHelper, cpu>(_helper, t, buf.get(), _resp, aInd[i]);
        mean += (val - mean) / algorithmFPType(i + 1);
    }
    return mean;
}

template <typename algorithmFPType, typename DataHelper, CpuType cpu>
algorithmFPType TrainBatchTaskBase<algorithmFPType, DataHelper, cpu>::computeOOBError(const dtrees::internal::Tree& t,
    size_t n, const IndexType* aInd)
{
    DAAL_ASSERT(n);
    //compute prediction error on each OOB row and get its mean online formulae (Welford)
    //TODO: can be threader_for() block
    ReadRows<algorithmFPType, cpu> x(const_cast<NumericTable*>(_data), aInd[0], 1);
    algorithmFPType mean = _helper.predictionError(t, x.get(), _resp, aInd[0], _threadCtx.oobBuf);
    for(size_t i = 1; i < n; ++i)
    {
        algorithmFPType val = _helper.predictionError(t, x.set(const_cast<NumericTable*>(_data), aInd[i], 1),
            _resp, aInd[i], _threadCtx.oobBuf);
        mean += (val - mean) / algorithmFPType(i + 1);
    }
    return mean;
}

} /* namespace internal */
} /* namespace training */
} /* namespace decision_forest */
} /* namespace algorithms */
} /* namespace daal */

#endif
