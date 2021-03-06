/* file: kmeans_container.h */
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
//  Implementation of K-means algorithm container -- a class that contains
//  Lloyd K-means kernels for supported architectures.
//--
*/

#include "kmeans_types.h"
#include "kmeans_batch.h"
#include "kmeans_distributed.h"
#include "kmeans_lloyd_kernel.h"

namespace daal
{
namespace algorithms
{
namespace kmeans
{

template<typename algorithmFPType, Method method, CpuType cpu>
BatchContainer<algorithmFPType, method, cpu>::BatchContainer(daal::services::Environment::env *daalEnv)
{
    __DAAL_INITIALIZE_KERNELS(internal::KMeansBatchKernel, method, algorithmFPType);
}

template<typename algorithmFPType, Method method, CpuType cpu>
BatchContainer<algorithmFPType, method, cpu>::~BatchContainer()
{
    __DAAL_DEINITIALIZE_KERNELS();
}

template<typename algorithmFPType, Method method, CpuType cpu>
services::Status BatchContainer<algorithmFPType, method, cpu>::compute()
{
    Input  *input  = static_cast<Input *>(_in );
    Result *result = static_cast<Result *>(_res);

    NumericTable *a[lastInputId + 1] =
    {
        input->get(data).get(),
        input->get(inputCentroids).get()
    };

    NumericTable *r[lastResultId + 1] =
    {
        result->get(centroids).get(),
        result->get(assignments).get(),
        result->get(objectiveFunction).get(),
        result->get(nIterations).get()
    };

    Parameter *par = static_cast<Parameter *>(_par);
    daal::services::Environment::env &env = *_env;
    __DAAL_CALL_KERNEL(env, internal::KMeansBatchKernel, __DAAL_KERNEL_ARGUMENTS(method, algorithmFPType), compute, a, r, par);
}

template<typename algorithmFPType, Method method, CpuType cpu>
DistributedContainer<step1Local, algorithmFPType, method, cpu>::DistributedContainer(daal::services::Environment::env *daalEnv)
{
    __DAAL_INITIALIZE_KERNELS(internal::KMeansDistributedStep1Kernel, method, algorithmFPType);
}

template<typename algorithmFPType, Method method, CpuType cpu>
DistributedContainer<step1Local, algorithmFPType, method, cpu>::~DistributedContainer()
{
    __DAAL_DEINITIALIZE_KERNELS();
}

template<typename algorithmFPType, Method method, CpuType cpu>
services::Status DistributedContainer<step1Local, algorithmFPType, method, cpu>::compute()
{
    Input         *input = static_cast<Input *>(_in  );
    PartialResult *pres  = static_cast<PartialResult *>(_pres);
    Parameter     *par   = static_cast<Parameter *>(_par );

    const size_t na = 2;
    NumericTable *a[na];
    a[0] = static_cast<NumericTable *>(input->get(data          ).get());
    a[1] = static_cast<NumericTable *>(input->get(inputCentroids).get());

    const size_t nr = 3 + (par->assignFlag != 0);
    NumericTable *r[4];
    r[0] = static_cast<NumericTable *>(pres->get(nObservations      ).get());
    r[1] = static_cast<NumericTable *>(pres->get(partialSums        ).get());
    r[2] = static_cast<NumericTable *>(pres->get(partialObjectiveFunction).get());
    if( par->assignFlag )
    {
        r[3] = static_cast<NumericTable *>(pres->get(partialAssignments).get());
    }

    daal::services::Environment::env &env = *_env;

    __DAAL_CALL_KERNEL(env, internal::KMeansDistributedStep1Kernel,
                       __DAAL_KERNEL_ARGUMENTS(method, algorithmFPType), compute, na, a, nr, r, par);
}

template<typename algorithmFPType, Method method, CpuType cpu>
services::Status DistributedContainer<step1Local, algorithmFPType, method, cpu>::finalizeCompute()
{
    PartialResult *pres  = static_cast<PartialResult *>(_pres);
    Result        *res   = static_cast<Result *>(_res );
    Parameter     *par   = static_cast<Parameter *>(_par );

    const size_t na = 1;
    NumericTable *a[na];
    a[0] = static_cast<NumericTable *>(pres->get(partialAssignments).get());

    const size_t nr = 1;
    NumericTable *r[nr];
    r[0] = static_cast<NumericTable *>(res->get(assignments).get());

    daal::services::Environment::env &env = *_env;

    __DAAL_CALL_KERNEL(env, internal::KMeansDistributedStep1Kernel,
                       __DAAL_KERNEL_ARGUMENTS(method, algorithmFPType), finalizeCompute, na, a, nr, r, par);
}

template<typename algorithmFPType, Method method, CpuType cpu>
DistributedContainer<step2Master, algorithmFPType, method, cpu>::DistributedContainer(daal::services::Environment::env *daalEnv)
{
    __DAAL_INITIALIZE_KERNELS(internal::KMeansDistributedStep2Kernel, method, algorithmFPType);
}

template<typename algorithmFPType, Method method, CpuType cpu>
DistributedContainer<step2Master, algorithmFPType, method, cpu>::~DistributedContainer()
{
    __DAAL_DEINITIALIZE_KERNELS();
}

template<typename algorithmFPType, Method method, CpuType cpu>
services::Status DistributedContainer<step2Master, algorithmFPType, method, cpu>::compute()
{
    DistributedStep2MasterInput *input = static_cast<DistributedStep2MasterInput *>(_in);
    data_management::DataCollection *dcInput = input->get(partialResults).get();
    PartialResult *pres = static_cast<PartialResult *>(_pres);

    size_t nPartials = dcInput->size();

    size_t na = nPartials * 3;
    NumericTable **a = new NumericTable*[na];
    for(size_t i = 0; i < nPartials; i++)
    {
        PartialResult *inPres = static_cast<PartialResult *>( (*dcInput)[i].get() );
        a[i * 3 + 0] = static_cast<NumericTable *>(inPres->get(nObservations).get());
        a[i * 3 + 1] = static_cast<NumericTable *>(inPres->get(partialSums    ).get());
        a[i * 3 + 2] = static_cast<NumericTable *>(inPres->get(partialObjectiveFunction    ).get());
    }

    const size_t nr = 3;
    NumericTable *r[nr];
    r[0] = static_cast<NumericTable *>(pres->get(nObservations).get());
    r[1] = static_cast<NumericTable *>(pres->get(partialSums    ).get());
    r[2] = static_cast<NumericTable *>(pres->get(partialObjectiveFunction  ).get());

    Parameter *par = static_cast<Parameter *>(_par);
    daal::services::Environment::env &env = *_env;

    services::Status s = __DAAL_CALL_KERNEL_STATUS(env, internal::KMeansDistributedStep2Kernel, __DAAL_KERNEL_ARGUMENTS(method, algorithmFPType), compute, na, a, nr, r, par);

    delete[] a;

    dcInput->clear();
    return s;
}

template<typename algorithmFPType, Method method, CpuType cpu>
services::Status DistributedContainer<step2Master, algorithmFPType, method, cpu>::finalizeCompute()
{
    PartialResult *pres = static_cast<PartialResult *>(_pres);
    Result *result = static_cast<Result *>(_res);

    const size_t na = 3;
    NumericTable *a[na];
    a[0] = static_cast<NumericTable *>(pres->get(nObservations).get());
    a[1] = static_cast<NumericTable *>(pres->get(partialSums    ).get());
    a[2] = static_cast<NumericTable *>(pres->get(partialObjectiveFunction    ).get());

    const size_t nr = 2;
    NumericTable *r[nr];
    r[0] = static_cast<NumericTable *>(result->get(centroids).get());
    r[1] = static_cast<NumericTable *>(result->get(objectiveFunction).get());

    Parameter *par = static_cast<Parameter *>(_par);
    daal::services::Environment::env &env = *_env;

    __DAAL_CALL_KERNEL(env, internal::KMeansDistributedStep2Kernel,
                       __DAAL_KERNEL_ARGUMENTS(method, algorithmFPType), finalizeCompute, na, a, nr, r, par);
}

} // namespace daal::algorithms::kmeans
} // namespace daal::algorithms
} // namespace daal
