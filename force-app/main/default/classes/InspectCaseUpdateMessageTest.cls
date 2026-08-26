@IsTest
private class InspectCaseUpdateMessageTest {

    /*
     * Helper method so each test can easily inspect
     * one customer message at a time.
     */
    private static InspectCaseUpdateMessage.Response inspect(String message) {
        InspectCaseUpdateMessage.Request req =
            new InspectCaseUpdateMessage.Request();

        req.customerMessage = message;

        List<InspectCaseUpdateMessage.Response> results =
            InspectCaseUpdateMessage.inspectMessages(
                new List<InspectCaseUpdateMessage.Request>{ req }
            );

        System.assertEquals(
            1,
            results.size(),
            'Exactly one response should be returned.'
        );

        return results[0];
    }


    @IsTest
    static void factualGrindingMessageReturnsSaveUpdate() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'The disc changer is grinding every time it moves up and down.'
            );

        System.assertEquals(
            'SAVE_UPDATE',
            result.route
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void factualChamberLightMessageReturnsSaveUpdate() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'The chamber light is constantly flickering now. ' +
                'It wont remain on or off, unless the machine is off.'
            );

        System.assertEquals(
            'SAVE_UPDATE',
            result.route
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    /*
     * Important regression test:
     * exact wording the customer may naturally use.
     */
    @IsTest
    static void addSomethingToCaseNumberReturnsResolveCase() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'I want to add something to case 00001153'
            );

        System.assertEquals(
            'RESOLVE_CASE',
            result.route
        );

        System.assertEquals(
            '00001153',
            result.requestedCaseNumber
        );
    }


    /*
     * Important regression test:
     * second phrase specifically requested.
     */
    @IsTest
    static void updateCaseNumberReturnsResolveCase() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'I want to update case 00001153'
            );

        System.assertEquals(
            'RESOLVE_CASE',
            result.route
        );

        System.assertEquals(
            '00001153',
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void uppercaseCaseReferenceReturnsResolveCase() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'I need to add something to Case 00001153'
            );

        System.assertEquals(
            'RESOLVE_CASE',
            result.route
        );

        System.assertEquals(
            '00001153',
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void lowercaseCaseReferenceReturnsResolveCase() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'please update case 00001153'
            );

        System.assertEquals(
            'RESOLVE_CASE',
            result.route
        );

        System.assertEquals(
            '00001153',
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void caseNumberKeywordReturnsResolveCase() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'I want to update case number 00001153'
            );

        System.assertEquals(
            'RESOLVE_CASE',
            result.route
        );

        System.assertEquals(
            '00001153',
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void caseNumberWithHashReturnsResolveCase() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'Can you add this to Case #00001153?'
            );

        System.assertEquals(
            'RESOLVE_CASE',
            result.route
        );

        System.assertEquals(
            '00001153',
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void factualMessageContainingCaseReferenceReturnsResolveCase() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'Regarding case 00001153, the chamber light is flickering now.'
            );

        System.assertEquals(
            'RESOLVE_CASE',
            result.route
        );

        System.assertEquals(
            '00001153',
            result.requestedCaseNumber
        );
    }


    /*
     * Supports the natural follow-up:
     *
     * AI: What Case Number would you like to update?
     * Customer: 00001153
     */
    @IsTest
    static void bareCaseNumberReturnsResolveCase() {

        InspectCaseUpdateMessage.Response result =
            inspect('00001153');

        System.assertEquals(
            'RESOLVE_CASE',
            result.route
        );

        System.assertEquals(
            '00001153',
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void preservesLeadingZeroes() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'Update Case 00000123'
            );

        System.assertEquals(
            'RESOLVE_CASE',
            result.route
        );

        System.assertEquals(
            '00000123',
            result.requestedCaseNumber,
            'Customer-visible Case Number must preserve leading zeroes.'
        );
    }


    @IsTest
    static void differentCaseWithoutNumberRequestsCaseNumber() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'I want to update a different case'
            );

        System.assertEquals(
            'REQUEST_CASE_NUMBER',
            result.route
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void anotherCaseWithoutNumberRequestsCaseNumber() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'I want to add something to another case'
            );

        System.assertEquals(
            'REQUEST_CASE_NUMBER',
            result.route
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void otherCaseWithoutNumberRequestsCaseNumber() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'I need to update my other case'
            );

        System.assertEquals(
            'REQUEST_CASE_NUMBER',
            result.route
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void updateCurrentCaseWithoutFactsRequestsUpdateText() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'I want to update the case'
            );

        System.assertEquals(
            'REQUEST_UPDATE_TEXT',
            result.route
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void addSomethingWithoutFactsRequestsUpdateText() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'I want to add something to the case'
            );

        System.assertEquals(
            'REQUEST_UPDATE_TEXT',
            result.route
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void updateIntentWithQuestionMarkRequestsUpdateText() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'Can I update this case?'
            );

        System.assertEquals(
            'REQUEST_UPDATE_TEXT',
            result.route
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void blankMessageRequestsUpdateText() {

        InspectCaseUpdateMessage.Response result =
            inspect('');

        System.assertEquals(
            'REQUEST_UPDATE_TEXT',
            result.route
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void whitespaceOnlyMessageRequestsUpdateText() {

        InspectCaseUpdateMessage.Response result =
            inspect('     ');

        System.assertEquals(
            'REQUEST_UPDATE_TEXT',
            result.route
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }



    /*
     * Read-only STATUS lookup with a valid customer-visible Case Number.
     */
    @IsTest
    static void statusCaseNumberReturnsStatusCase() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'What is the status of Case 00001163?'
            );

        System.assertEquals(
            'STATUS_CASE',
            result.route
        );

        System.assertEquals(
            '00001163',
            result.requestedCaseNumber
        );
    }


    /*
     * STATUS lookup using the customer-facing "service request" wording.
     */
    @IsTest
    static void serviceRequestStatusReturnsStatusCase() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'Can you check service request 00001163?'
            );

        System.assertEquals(
            'STATUS_CASE',
            result.route
        );

        System.assertEquals(
            '00001163',
            result.requestedCaseNumber
        );
    }


    /*
     * Regression test for Test 6E:
     * preserve STATUS intent when no usable customer-visible Case Number
     * was supplied.
     */
    @IsTest
    static void statusRequestWithoutCaseNumberRequestsStatusCaseNumber() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'Can you check the status of this service request?'
            );

        System.assertEquals(
            'REQUEST_STATUS_CASE_NUMBER',
            result.route,
            'A read-only status request without a usable Case Number must preserve STATUS intent.'
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    /*
     * Exact Test 6E regression:
     * a customer-supplied Salesforce record Id must not be accepted as
     * a Case Number, but the original STATUS intent must be preserved.
     */
    @IsTest
    static void statusRequestWithSalesforceIdRequestsStatusCaseNumber() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'Can you check the status of this service request? 500gK00001Hw386QAB'
            );

        System.assertEquals(
            'REQUEST_STATUS_CASE_NUMBER',
            result.route,
            'The raw Salesforce Id must be rejected while preserving the read-only STATUS intent.'
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber,
            'A Salesforce record Id must never be returned as the customer-visible Case Number.'
        );
    }


    /*
     * Same regression check with a generic 18-character Salesforce Id.
     */
    @IsTest
    static void statusRequestWithEighteenCharacterSalesforceIdRequestsStatusCaseNumber() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'What is the status of this service request? 500ABC123DEF456XYZ'
            );

        System.assertEquals(
            'REQUEST_STATUS_CASE_NUMBER',
            result.route
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    /*
     * UPDATE remains higher priority than STATUS when both intents
     * appear with a valid customer-visible Case Number.
     */
    @IsTest
    static void updateIntentStillWinsOverStatusIntent() {

        InspectCaseUpdateMessage.Response result =
            inspect(
                'Can you check the status and update Case 00001163?'
            );

        System.assertEquals(
            'RESOLVE_CASE',
            result.route
        );

        System.assertEquals(
            '00001163',
            result.requestedCaseNumber
        );
    }


    /*
     * A raw Salesforce record Id must NOT be interpreted
     * as a customer-visible Case Number.
     */
    @IsTest
    static void fifteenCharacterSalesforceIdDoesNotResolveCase() {

        InspectCaseUpdateMessage.Response result =
            inspect('500ABC123DEF456');

        System.assertEquals(
            'SAVE_UPDATE',
            result.route,
            'A Salesforce record Id must not be interpreted as a Case Number.'
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    @IsTest
    static void eighteenCharacterSalesforceIdDoesNotResolveCase() {

        InspectCaseUpdateMessage.Response result =
            inspect('500ABC123DEF456XYZ');

        System.assertEquals(
            'SAVE_UPDATE',
            result.route,
            'An 18-character Salesforce Id must not be interpreted as a Case Number.'
        );

        System.assertEquals(
            null,
            result.requestedCaseNumber
        );
    }


    /*
     * Verify Invocable bulk behavior as well.
     */
    @IsTest
    static void handlesMultipleRequestsInOneInvocation() {

        InspectCaseUpdateMessage.Request req1 =
            new InspectCaseUpdateMessage.Request();
        req1.customerMessage =
            'The chamber light is flickering now.';

        InspectCaseUpdateMessage.Request req2 =
            new InspectCaseUpdateMessage.Request();
        req2.customerMessage =
            'I want to update case 00001153';

        InspectCaseUpdateMessage.Request req3 =
            new InspectCaseUpdateMessage.Request();
        req3.customerMessage =
            'I want to update a different case';

        List<InspectCaseUpdateMessage.Response> results =
            InspectCaseUpdateMessage.inspectMessages(
                new List<InspectCaseUpdateMessage.Request>{
                    req1,
                    req2,
                    req3
                }
            );

        System.assertEquals(
            3,
            results.size()
        );

        System.assertEquals(
            'SAVE_UPDATE',
            results[0].route
        );

        System.assertEquals(
            'RESOLVE_CASE',
            results[1].route
        );

        System.assertEquals(
            '00001153',
            results[1].requestedCaseNumber
        );

        System.assertEquals(
            'REQUEST_CASE_NUMBER',
            results[2].route
        );
    }
}