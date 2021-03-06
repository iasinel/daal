/* file: Parameter.java */
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
 * @ingroup svd
 * @{
 */
package com.intel.daal.algorithms.svd;

import com.intel.daal.services.DaalContext;

/**
 * <a name="DAAL-CLASS-ALGORITHMS__SVD__PARAMETER"></a>
 * @brief Parameters of the compute() method of the SVD algorithm
 */
public class Parameter extends com.intel.daal.algorithms.Parameter {
    /** @private */
    static {
        System.loadLibrary("JavaAPI");
    }

    public Parameter(DaalContext context, long cParameter) {
        super(context);
        this.cObject = cParameter;
    }

    /**
     *  Sets the format of the matrix of left singular vectors
     *  @param format  Format of the matrix of left singular vectors
     */
    public void setLeftSingularMatrixFormat(ResultFormat format) {
        cSetLeftSingularMatrixFormat(this.cObject, format.getValue());
    }

    /**
     *  Sets the format of the matrix of right singular vectors
     *  @param format  Format of the matrix of right singular vectors
     */
    public void setRightSingularMatrixFormat(ResultFormat format) {
        cSetRightSingularMatrixFormat(this.cObject, format.getValue());
    }

    /**
     *  Gets the format of the matrix of left singular vectors
     *  @return  Format of the matrix of left singular vectors
     */
    public ResultFormat getLeftSingularMatrixFormat() {
        ResultFormat format = ResultFormat.notRequired;
        int flag = cGetLeftSingularMatrixFormat(this.cObject);
        if (flag == ResultFormat.notRequired.getValue()) {
            format = ResultFormat.notRequired;
        } else {
            if (flag == ResultFormat.requiredInPackedForm.getValue()) {
                format = ResultFormat.requiredInPackedForm;
            }
        }

        return format;
    }

    /**
     *  Gets the format of the matrix of right singular vectors
     *  @return  Format of the matrix of right singular vectors
     */
    public ResultFormat getRightSingularMatrixFormat() {
        ResultFormat format = ResultFormat.notRequired;
        int flag = cGetRightSingularMatrixFormat(this.cObject);
        if (flag == ResultFormat.notRequired.getValue()) {
            format = ResultFormat.notRequired;
        } else {
            if (flag == ResultFormat.requiredInPackedForm.getValue()) {
                format = ResultFormat.requiredInPackedForm;
            }
        }

        return format;
    }

    private native long cParInit();

    private native void cSetLeftSingularMatrixFormat(long algAddr, int format);

    private native void cSetRightSingularMatrixFormat(long algAddr, int format);

    private native int cGetLeftSingularMatrixFormat(long algAddr);

    private native int cGetRightSingularMatrixFormat(long algAddr);
}
/** @} */
