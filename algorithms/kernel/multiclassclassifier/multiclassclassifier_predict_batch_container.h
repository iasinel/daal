/* file: multiclassclassifier_predict_batch_container.h */
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
//  Implementation of Multi-class classifier prediction algorithm container --
//  a class that contains Multi-class classifier kernels for supported
//  architectures.
//--
*/

#include "multi_class_classifier_predict.h"
#include "multiclassclassifier_predict_kernel.h"
#include "multiclassclassifier_predict_mccwu_kernel.h"
#include "kernel.h"

using namespace daal::data_management;

namespace daal
{
namespace algorithms
{
namespace multi_class_classifier
{
namespace prediction
{

template<typename algorithmFPType, prediction::Method pmethod, training::Method tmethod, CpuType cpu>
BatchContainer<algorithmFPType, pmethod, tmethod, cpu>::BatchContainer(daal::services::Environment::env *daalEnv)
{
    __DAAL_INITIALIZE_KERNELS(internal::MultiClassClassifierPredictKernel, pmethod, tmethod, algorithmFPType);
}

template<typename algorithmFPType, prediction::Method pmethod, training::Method tmethod, CpuType cpu>
BatchContainer<algorithmFPType, pmethod, tmethod, cpu>::~BatchContainer()
{
    __DAAL_DEINITIALIZE_KERNELS();
}

template<typename algorithmFPType, prediction::Method pmethod, training::Method tmethod, CpuType cpu>
services::Status BatchContainer<algorithmFPType, pmethod, tmethod, cpu>::compute()
{
    classifier::prediction::Input *input = static_cast<classifier::prediction::Input *>(_in);
    classifier::prediction::Result *result = static_cast<classifier::prediction::Result *>(_res);

    NumericTable *a = static_cast<NumericTable *>(input->get(classifier::prediction::data).get());
    multi_class_classifier::Model *m = static_cast<multi_class_classifier::Model *>(input->get(classifier::prediction::model).get());
    NumericTable *r[1];
    r[0] = static_cast<NumericTable *>(result->get(classifier::prediction::prediction).get());

    daal::algorithms::Parameter *par = _par;
    daal::services::Environment::env &env = *_env;
    __DAAL_CALL_KERNEL(env, internal::MultiClassClassifierPredictKernel,
                       __DAAL_KERNEL_ARGUMENTS(pmethod, tmethod,  algorithmFPType), compute, a, m, r[0], par);
}

} // namespace prediction

} // namespace multi_class_classifier

} // namespace algorithms

} // namespace daal
