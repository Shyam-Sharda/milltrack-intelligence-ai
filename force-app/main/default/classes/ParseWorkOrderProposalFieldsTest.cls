@IsTest
private class ParseWorkOrderProposalFieldsTest {
    @IsTest
    static void parsesValidProposalText() {
        ParseWorkOrderProposalFields.Request request =
            new ParseWorkOrderProposalFields.Request();
        request.proposalText =
            'PROBLEM SUMMARY:\n' +
            'Machine stopped during milling and displays error 101D.\n\n' +
            'RECOMMENDED SOLUTION:\n' +
            '- Inspect collet area.\n' +
            '- Verify air pressure.\n\n' +
            'TECHNICIAN NOTES:\n' +
            'Bring diagnostic tools.\n\n' +
            'RECOMMENDED PARTS:\n' +
            'None identified\n\n' +
            'PREVIOUS FAILURE:\n' +
            'false\n\n' +
            'PRIORITY:\n' +
            'High';

        Test.startTest();
        List<ParseWorkOrderProposalFields.Response> results =
            ParseWorkOrderProposalFields.parseProposalFields(
                new List<ParseWorkOrderProposalFields.Request>{
                    request
                }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(
            results[0].problemSummary.contains('Machine stopped')
        );
        System.assert(
            results[0].recommendedSolution.contains('Inspect collet')
        );
        System.assertEquals(
            'Bring diagnostic tools.',
            results[0].technicianNotes
        );
        System.assertEquals(
            'None identified',
            results[0].recommendedParts
        );
        System.assertEquals('', results[0].recommendedPartsJson);
        System.assertEquals(false, results[0].previousFailure);
        System.assertEquals('High', results[0].priority);
    }

    @IsTest
    static void preservesPlainTextRecommendedParts() {
        ParseWorkOrderProposalFields.Request request =
            new ParseWorkOrderProposalFields.Request();
        request.proposalText =
            'PROBLEM SUMMARY:\nRepeat spindle issue.\n\n' +
            'RECOMMENDED SOLUTION:\nInspect spindle.\n\n' +
            'TECHNICIAN NOTES:\nUse prior service history.\n\n' +
            'RECOMMENDED PARTS:\n- Spindle assembly\n\n' +
            'PREVIOUS FAILURE:\ntrue\n\n' +
            'PRIORITY:\nCritical';

        Test.startTest();
        List<ParseWorkOrderProposalFields.Response> results =
            ParseWorkOrderProposalFields.parseProposalFields(
                new List<ParseWorkOrderProposalFields.Request>{
                    request
                }
            );
        Test.stopTest();

        System.assertEquals(
            '- Spindle assembly',
            results[0].recommendedParts
        );
        System.assertEquals('', results[0].recommendedPartsJson);
        System.assertEquals(true, results[0].previousFailure);
        System.assertEquals('Critical', results[0].priority);
    }

    @IsTest
    static void formatsLegacyJsonRecommendedParts() {
        ParseWorkOrderProposalFields.Request request =
            new ParseWorkOrderProposalFields.Request();
        request.proposalText =
            'PROBLEM SUMMARY:\nLegacy structured proposal.\n\n' +
            'RECOMMENDED PARTS:\n' +
            '```json\n' +
            '{"parts":[{"name":"Spindle assembly","quantity":2}]}' +
            '\n```\n\n' +
            'PREVIOUS FAILURE:\nfalse\n\n' +
            'PRIORITY:\nMedium';

        Test.startTest();
        List<ParseWorkOrderProposalFields.Response> results =
            ParseWorkOrderProposalFields.parseProposalFields(
                new List<ParseWorkOrderProposalFields.Request>{
                    request
                }
            );
        Test.stopTest();

        System.assert(
            results[0].recommendedParts.contains('Spindle assembly')
        );
        System.assert(
            results[0].recommendedParts.contains('Quantity: 2')
        );
        System.assert(
            results[0].recommendedPartsJson.contains('"parts"')
        );
    }

    @IsTest
    static void handlesMissingSectionsWithoutFailing() {
        ParseWorkOrderProposalFields.Request request =
            new ParseWorkOrderProposalFields.Request();
        request.proposalText =
            'PROBLEM SUMMARY:\nOnly summary exists.';

        Test.startTest();
        List<ParseWorkOrderProposalFields.Response> results =
            ParseWorkOrderProposalFields.parseProposalFields(
                new List<ParseWorkOrderProposalFields.Request>{
                    request
                }
            );
        Test.stopTest();

        System.assertEquals(
            'Only summary exists.',
            results[0].problemSummary
        );
        System.assertEquals('', results[0].recommendedSolution);
        System.assertEquals('', results[0].technicianNotes);
        System.assertEquals('', results[0].recommendedParts);
        System.assertEquals('', results[0].recommendedPartsJson);
        System.assertEquals(false, results[0].previousFailure);
        System.assertEquals('', results[0].priority);
    }

    @IsTest
    static void handlesBlankInputWithoutFailing() {
        ParseWorkOrderProposalFields.Request request =
            new ParseWorkOrderProposalFields.Request();
        request.proposalText = null;

        Test.startTest();
        List<ParseWorkOrderProposalFields.Response> results =
            ParseWorkOrderProposalFields.parseProposalFields(
                new List<ParseWorkOrderProposalFields.Request>{
                    request
                }
            );
        Test.stopTest();

        System.assertEquals('', results[0].problemSummary);
        System.assertEquals('', results[0].recommendedSolution);
        System.assertEquals('', results[0].technicianNotes);
        System.assertEquals('', results[0].recommendedParts);
        System.assertEquals('', results[0].recommendedPartsJson);
        System.assertEquals(false, results[0].previousFailure);
        System.assertEquals('', results[0].priority);
    }
}