/*
 * Copyright (C) 2011-2021 Intel Corporation. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Intel Corporation nor the names of its
 *     contributors may be used to endorse or promote products derived
 *     from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

'use strict';

const InternalError = require('./errors').InternalError;

const STATUSES = {
    STATUS_OK:                     { httpCode: 200, name: 'STATUS_OK' },
    STATUS_CREATED:                { httpCode: 201, name: 'STATUS_CREATED' },
    STATUS_INTERNAL_ERROR:         { httpCode: 500, name: 'STATUS_INTERNAL_ERROR' },
    STATUS_BAD_REQUEST:            { httpCode: 400, name: 'STATUS_BAD_REQUEST' },
    STATUS_NOT_FOUND:              { httpCode: 404, name: 'STATUS_NOT_FOUND' },
    STATUS_GONE:                   { httpCode: 410, name: 'STATUS_GONE' },
    STATUS_PAYLOAD_TOO_LARGE:      { httpCode: 413, name: 'STATUS_PAYLOAD_TOO_LARGE' },
    STATUS_UNSUPPORTED_MEDIA_TYPE: { httpCode: 415, name: 'STATUS_UNSUPPORTED_MEDIA_TYPE' },
    STATUS_SERVICE_UNAVAILABLE:    { httpCode: 503, name: 'STATUS_SERVICE_UNAVAILABLE' }
};

class GenericResponse {
    constructor(status, log) {
        if (!status.httpCode || !status.name) {
            log.error(`Cannot construct response because 'status' object is invalid: ${JSON.stringify(status)}.`);
            throw new InternalError();
        }
        this.httpCode = status.httpCode;
        this.jsonBody = { status: status.name };
    }
}

class InternalErrorResponse extends GenericResponse {
    constructor(log) {
        super(STATUSES.STATUS_INTERNAL_ERROR, log);
    }
}

class BadRequestResponse extends GenericResponse {
    constructor(log) {
        super(STATUSES.STATUS_BAD_REQUEST, log);
    }
}

/**
 * @typedef Response
 * @type jsonBody
 * @property {number} httpCode
 */

/**
 * Sets response body and status
 * @param response
 * @param ctx
 */
function setResponse(response, ctx) {
    ctx.body = response.jsonBody;
    ctx.status = response.httpCode;
}

module.exports = {
    STATUSES,
    setResponse,
    GenericResponse,
    InternalErrorResponse,
    BadRequestResponse
};
