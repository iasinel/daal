/* file: TrainingResult.java */
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

/**
 * @ingroup decision_forest_regression_training
 * @{
 */
package com.intel.daal.algorithms.decision_forest.regression.training;

import com.intel.daal.algorithms.ComputeMode;
import com.intel.daal.algorithms.decision_forest.regression.Model;
import com.intel.daal.algorithms.decision_forest.regression.training.ResultNumericTableId;
import com.intel.daal.algorithms.decision_forest.regression.training.TrainingResultId;
import com.intel.daal.data_management.data.Factory;
import com.intel.daal.data_management.data.NumericTable;
import com.intel.daal.services.DaalContext;
import com.intel.daal.algorithms.Precision;

/**
 * <a name="DAAL-CLASS-ALGORITHMS__DECISION_FOREST__REGRESSION__TRAINING__TRAININGRESULT"></a>
 * @brief Provides methods to access final results obtained with the compute() method of the decision forest regression training algorithm
 *                                                                                                in the batch processing mode.
 */
public final class TrainingResult extends com.intel.daal.algorithms.Result {
    /** @private */
    static {
        System.loadLibrary("JavaAPI");
    }

    public TrainingResult(DaalContext context, long cAlgorithm, Precision prec, ComputeMode cmode) {
        super(context);
        this.cObject = cGetResult(cAlgorithm, prec.getValue(), cmode.getValue());
    }

    /**
     * Returns the final result of the decision forest regression training algorithms
     * @param id   Identifier of the result
     * @return         %Result that corresponds to the given identifier
     */
    public Model get(TrainingResultId id) {
        if (id != TrainingResultId.model) {
            throw new IllegalArgumentException("id unsupported");
        }
        return new Model(getContext(), cGetModel(cObject, TrainingResultId.model.getValue()));
    }
    public NumericTable get(ResultNumericTableId id) {
        if (id == ResultNumericTableId.variableImportance || id == ResultNumericTableId.outOfBagError) {
            return (NumericTable)Factory.instance().createObject(getContext(), cGetResultTable(cObject, id.getValue()));
        } else {
            throw new IllegalArgumentException("id unsupported");
        }
    }

    private native long cGetResult(long algAddr, int prec, int method);
    private native long cGetModel(long resAddr, int id);
    private native long cGetResultTable(long resAddr, int id);
}
/** @} */
