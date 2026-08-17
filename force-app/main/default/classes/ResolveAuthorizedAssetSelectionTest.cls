@IsTest
private class ResolveAuthorizedAssetSelectionTest {

    // Synthetic Salesforce IDs.
    // These records do not need to exist because the resolver never queries them.
    private static final String ASSET_ID_1 = '02i000000000001';
    private static final String ASSET_ID_2 = '02i000000000002';
    private static final String ACCOUNT_ID = '001000000000001';

    /*
     * -------------------------------------------------------------------------
     * NEW DETERMINISTIC TEXT-SELECTION TESTS
     * -------------------------------------------------------------------------
     */

    @IsTest
    static void resolvesNumericTextSelection() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1 + ';2=' + ASSET_ID_2;

        request.selectedOptionText = '2';

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(
            true,
            response.success,
            'An exact numeric option returned by the customer should resolve successfully.'
        );

        System.assertEquals(
            'CONFIRMED',
            response.statusCode
        );

        System.assertEquals(
            String.valueOf((Id) ASSET_ID_2),
            response.confirmedAssetId,
            'Text option 2 must resolve only to the Asset mapped to trusted option 2.'
        );

        System.assertEquals(
            'The selected machine was confirmed.',
            response.customerMessage
        );
    }

    @IsTest
    static void resolvesNumericTextSelectionWithWhitespace() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1 + ';2=' + ASSET_ID_2;

        request.selectedOptionText = '  1  ';

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('CONFIRMED', response.statusCode);

        System.assertEquals(
            String.valueOf((Id) ASSET_ID_1),
            response.confirmedAssetId,
            'Whitespace around an otherwise valid numeric selection should be ignored.'
        );
    }

    @IsTest
    static void resolvesPositiveConfirmationWhenExactlyOneAssetExists() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1;

        request.selectedOptionText = 'yes it is';

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(
            true,
            response.success,
            'A positive confirmation may resolve automatically when exactly one trusted Asset exists.'
        );

        System.assertEquals(
            'CONFIRMED',
            response.statusCode
        );

        System.assertEquals(
            String.valueOf((Id) ASSET_ID_1),
            response.confirmedAssetId
        );
    }

    @IsTest
    static void rejectsAmbiguousYesWhenMultipleAssetsExist() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1 + ';2=' + ASSET_ID_2;

        request.selectedOptionText = 'yes';

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(
            false,
            response.success,
            'A generic yes must not select between multiple authorized Assets.'
        );

        System.assertEquals(
            'INVALID_SELECTION',
            response.statusCode
        );

        System.assertEquals(
            '',
            response.confirmedAssetId
        );
    }

    @IsTest
    static void rejectsRawAssetIdAsCustomerSelection() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1 + ';2=' + ASSET_ID_2;

        /*
         * Even though this happens to be an Asset ID contained in the trusted
         * reference map, a customer-entered Salesforce record ID must NEVER
         * independently authorize or confirm an Asset.
         */
        request.selectedOptionText = ASSET_ID_1;

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(
            false,
            response.success,
            'A raw Salesforce Asset ID typed by the customer must be rejected.'
        );

        System.assertEquals(
            'INVALID_SELECTION',
            response.statusCode
        );

        System.assertEquals(
            '',
            response.confirmedAssetId
        );
    }

    @IsTest
    static void rejectsTextOptionNotInAuthorizedReferences() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1 + ';2=' + ASSET_ID_2;

        request.selectedOptionText = '3';

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals('INVALID_SELECTION', response.statusCode);
        System.assertEquals('', response.confirmedAssetId);
    }

    /*
     * -------------------------------------------------------------------------
     * BACKWARD-COMPATIBILITY TESTS
     * -------------------------------------------------------------------------
     */

    @IsTest
    static void resolvesLegacyIntegerSelection() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1 + ';2=' + ASSET_ID_2;

        request.selectedOptionNumber = 2;

        Test.startTest();

        List<ResolveAuthorizedAssetSelection.Response> responses =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(
            1,
            responses.size(),
            'One response should be returned.'
        );

        ResolveAuthorizedAssetSelection.Response response =
            responses[0];

        System.assertEquals(
            true,
            response.success,
            'The legacy Integer input must continue working during migration.'
        );

        System.assertEquals(
            'CONFIRMED',
            response.statusCode
        );

        System.assertEquals(
            String.valueOf((Id) ASSET_ID_2),
            response.confirmedAssetId,
            'The resolver must return only the Asset ID mapped to option 2.'
        );

        System.assertEquals(
            'The selected machine was confirmed.',
            response.customerMessage
        );
    }

    @IsTest
    static void legacyIntegerTakesPrecedenceDuringMigration() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1 + ';2=' + ASSET_ID_2;

        /*
         * This should only occur during migration.
         * The legacy Integer input wins if both happen to be supplied.
         */
        request.selectedOptionNumber = 2;
        request.selectedOptionText = '1';

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('CONFIRMED', response.statusCode);

        System.assertEquals(
            String.valueOf((Id) ASSET_ID_2),
            response.confirmedAssetId,
            'Legacy Integer input should retain precedence until it is removed.'
        );
    }

    @IsTest
    static void rejectsLegacyOptionNotInAuthorizedReferences() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1 + ';2=' + ASSET_ID_2;

        request.selectedOptionNumber = 3;

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals('INVALID_SELECTION', response.statusCode);
        System.assertEquals('', response.confirmedAssetId);
    }

    /*
     * -------------------------------------------------------------------------
     * VALIDATION / FAILURE TESTS
     * -------------------------------------------------------------------------
     */

    @IsTest
    static void rejectsMissingSelection() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1;

        // Both selection inputs intentionally left null.

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals('INVALID_SELECTION', response.statusCode);
        System.assertEquals('', response.confirmedAssetId);
    }

    @IsTest
    static void rejectsBlankTextSelection() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1;

        request.selectedOptionText = '   ';

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals('INVALID_SELECTION', response.statusCode);
        System.assertEquals('', response.confirmedAssetId);
    }

    @IsTest
    static void rejectsMissingAuthorizedReferences() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences = '';
        request.selectedOptionText = '1';

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(false, response.success);

        System.assertEquals(
            'MISSING_AUTHORIZED_REFERENCES',
            response.statusCode
        );

        System.assertEquals('', response.confirmedAssetId);
    }

    @IsTest
    static void rejectsNonAssetSalesforceIdInTrustedReferences() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        /*
         * Syntactically valid Salesforce ID, but 001 identifies an Account
         * rather than an Asset.
         */
        request.authorizedAssetReferences =
            '1=' + ACCOUNT_ID;

        request.selectedOptionText = '1';

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(false, response.success);

        /*
         * The updated controller parses the trusted reference map before
         * resolving the customer selection. Because no valid Asset reference
         * survives parsing, the trusted reference set is treated as missing.
         */
        System.assertEquals(
            'MISSING_AUTHORIZED_REFERENCES',
            response.statusCode
        );

        System.assertEquals('', response.confirmedAssetId);
    }

    @IsTest
    static void safelyIgnoresMalformedReferenceEntries() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            'garbage;' +
            '1=not-a-salesforce-id;' +
            '2=' + ASSET_ID_2 + ';' +
            'bad=entry';

        request.selectedOptionText = '2';

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('CONFIRMED', response.statusCode);

        System.assertEquals(
            String.valueOf((Id) ASSET_ID_2),
            response.confirmedAssetId,
            'Malformed entries must not prevent a separate valid trusted Asset mapping from resolving.'
        );
    }

    @IsTest
    static void rejectsArbitraryTextSelection() {

        ResolveAuthorizedAssetSelection.Request request =
            new ResolveAuthorizedAssetSelection.Request();

        request.authorizedAssetReferences =
            '1=' + ASSET_ID_1 + ';2=' + ASSET_ID_2;

        request.selectedOptionText = 'the Roland machine';

        Test.startTest();

        ResolveAuthorizedAssetSelection.Response response =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ request }
            )[0];

        Test.stopTest();

        System.assertEquals(
            false,
            response.success,
            'Machine names typed by the customer must not independently resolve an authorized Asset.'
        );

        System.assertEquals('INVALID_SELECTION', response.statusCode);
        System.assertEquals('', response.confirmedAssetId);
    }

    @IsTest
    static void handlesNullRequestSafely() {

        Test.startTest();

        List<ResolveAuthorizedAssetSelection.Response> responses =
            ResolveAuthorizedAssetSelection.resolveSelections(
                new List<ResolveAuthorizedAssetSelection.Request>{ null }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(false, responses[0].success);

        System.assertEquals(
            'MISSING_AUTHORIZED_REFERENCES',
            responses[0].statusCode
        );

        System.assertEquals('', responses[0].confirmedAssetId);
    }

    @IsTest
    static void handlesNullRequestListSafely() {

        Test.startTest();

        List<ResolveAuthorizedAssetSelection.Response> responses =
            ResolveAuthorizedAssetSelection.resolveSelections(null);

        Test.stopTest();

        System.assertEquals(
            0,
            responses.size(),
            'A null request list should safely return an empty response list.'
        );
    }
}