@isTest
private class ParsePartRecommendationsTest {

    @isTest
    static void testValidJsonMultipleParts() {
        ParsePartRecommendations.Request req = new ParsePartRecommendations.Request();
        req.recommendedParts = 
            '{"parts":[' +
            '{"Name":"Spindle Motor","quantity":1},' +
            '{"Name":"Front Cover Switch","quantity":2}' +
            ']}';

        Test.startTest();
        List<ParsePartRecommendations.Result> results = ParsePartRecommendations.parseParts(
            new List<ParsePartRecommendations.Request>{ req });
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals('Spindle Motor', results[0].Name);
        System.assertEquals(1, results[0].quantity);
        System.assertEquals('Front Cover Switch', results[1].Name);
        System.assertEquals(2, results[1].quantity);
    }

    @isTest
    static void testBlankInputReturnsEmptyList() {
        ParsePartRecommendations.Request req = new ParsePartRecommendations.Request();
        req.recommendedParts = '';

        Test.startTest();
        List<ParsePartRecommendations.Result> results =
            ParsePartRecommendations.parseParts(new List<ParsePartRecommendations.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @isTest
    static void testMissingQuantityDefaultsToOne() {
        ParsePartRecommendations.Request req = new ParsePartRecommendations.Request();
        req.recommendedParts =
            '{"parts":[{"Name":"Collet"}]}';

        Test.startTest();
        List<ParsePartRecommendations.Result> results =
            ParsePartRecommendations.parseParts(new List<ParsePartRecommendations.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Collet', results[0].Name);
        System.assertEquals(1, results[0].quantity);
    }

    @isTest
    static void testInvalidJsonFallback() {
        ParsePartRecommendations.Request req = new ParsePartRecommendations.Request();
        req.recommendedParts = 'Spindle Motor';

        Test.startTest();
        List<ParsePartRecommendations.Result> results =
            ParsePartRecommendations.parseParts(new List<ParsePartRecommendations.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Spindle Motor', results[0].Name);
        System.assertEquals(1, results[0].quantity);
    }


}