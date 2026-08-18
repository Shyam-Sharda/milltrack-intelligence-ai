@IsTest
private class GenerateServiceRequestFingerprintTest {

    @IsTest
    static void sameRequestProducesSameFingerprint() {
        GenerateServiceRequestFingerprint.Request requestOne = new GenerateServiceRequestFingerprint.Request();
        requestOne.authorizedAssetId = '02i000000000001AAA';
        requestOne.originalServiceRequest ='My milling machine occasionally makes a faint squeaking noise.';

        GenerateServiceRequestFingerprint.Request requestTwo = new GenerateServiceRequestFingerprint.Request();
        // Deliberately vary casing and whitespace.
        requestTwo.authorizedAssetId = '  02I000000000001AAA  ';
        requestTwo.originalServiceRequest = '  MY MILLING MACHINE   occasionally makes a faint squeaking noise.  ';

        Test.startTest();
        List<GenerateServiceRequestFingerprint.Result> firstResults =
            GenerateServiceRequestFingerprint.generate(new List<GenerateServiceRequestFingerprint.Request>{requestOne});

        List<GenerateServiceRequestFingerprint.Result> secondResults =
            GenerateServiceRequestFingerprint.generate(new List<GenerateServiceRequestFingerprint.Request>{requestTwo});
        Test.stopTest();

        System.assertEquals(1, firstResults.size(),
            'Expected one result for the first request.'
        );

        System.assertEquals(1, secondResults.size(),
            'Expected one result for the second request.'
        );

        System.assertEquals(true, firstResults[0].success,
            'First fingerprint generation should succeed.'
        );

        System.assertEquals(true, secondResults[0].success,
            'Second fingerprint generation should succeed.'
        );

        System.assertEquals('FINGERPRINT_CREATED', firstResults[0].statusCode,
            'Expected successful fingerprint status.'
        );

        System.assertEquals('FINGERPRINT_CREATED', secondResults[0].statusCode,
            'Expected successful fingerprint status.'
        );

        System.assertEquals(firstResults[0].fingerprint, secondResults[0].fingerprint,
            'Case and repeated whitespace differences should not change the fingerprint.'
        );

        System.assertEquals(64, firstResults[0].fingerprint.length(),
            'SHA-256 fingerprint encoded as hexadecimal should contain 64 characters.'
         );

        System.assert(Pattern.matches('^[0-9a-f]{64}$', firstResults[0].fingerprint),
            'Fingerprint should contain exactly 64 lowercase hexadecimal characters.'
        );
    }


    @IsTest
    static void differentRequestProducesDifferentFingerprint() {
        GenerateServiceRequestFingerprint.Request requestOne = new GenerateServiceRequestFingerprint.Request();
        requestOne.authorizedAssetId = '02i000000000001AAA';
        requestOne.originalServiceRequest = 'My milling machine occasionally makes a faint squeaking noise.';

        GenerateServiceRequestFingerprint.Request requestTwo = new GenerateServiceRequestFingerprint.Request();
        requestTwo.authorizedAssetId = '02i000000000001AAA';
        requestTwo.originalServiceRequest = 'My milling machine has completely stopped working.';

        Test.startTest();
        List<GenerateServiceRequestFingerprint.Result> results =
            GenerateServiceRequestFingerprint.generate(new List<GenerateServiceRequestFingerprint.Request>{requestOne, requestTwo});
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Expected one fingerprint result per input.');
        System.assertEquals(true, results[0].success);
        System.assertEquals(true, results[1].success);
        System.assertNotEquals(results[0].fingerprint, results[1].fingerprint,
            'Different customer service requests for the same Asset must produce different fingerprints.'
        );
    }


    @IsTest
    static void differentAssetProducesDifferentFingerprint() {
        String sameServiceRequest = 'My milling machine occasionally makes a faint squeaking noise.';

        GenerateServiceRequestFingerprint.Request requestOne = new GenerateServiceRequestFingerprint.Request();
        requestOne.authorizedAssetId = '02i000000000001AAA';
        requestOne.originalServiceRequest = sameServiceRequest;

        GenerateServiceRequestFingerprint.Request requestTwo = new GenerateServiceRequestFingerprint.Request();
        requestTwo.authorizedAssetId = '02i000000000002AAA';
        requestTwo.originalServiceRequest = sameServiceRequest;

        Test.startTest();
        List<GenerateServiceRequestFingerprint.Result> results =
            GenerateServiceRequestFingerprint.generate(new List<GenerateServiceRequestFingerprint.Request>{requestOne, requestTwo});
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals(true, results[1].success);
        System.assertNotEquals(results[0].fingerprint, results[1].fingerprint, 
            'The same service request for different Assets must produce different fingerprints.');
    }


    @IsTest
    static void missingAssetReturnsMissingRequiredInput() {
        GenerateServiceRequestFingerprint.Request request = new GenerateServiceRequestFingerprint.Request();
        request.authorizedAssetId = null;
        request.originalServiceRequest = 'My milling machine is making a grinding noise.';

        Test.startTest();
        List<GenerateServiceRequestFingerprint.Result> results =
            GenerateServiceRequestFingerprint.generate(new List<GenerateServiceRequestFingerprint.Request>{request});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success, 'Fingerprint generation must fail when the Asset ID is missing.');
        System.assertEquals('MISSING_REQUIRED_INPUT', results[0].statusCode);
        System.assertEquals(null, results[0].fingerprint, 'No fingerprint should be returned for invalid input.');
    }


    @IsTest
    static void missingServiceRequestReturnsMissingRequiredInput() {
        GenerateServiceRequestFingerprint.Request request = new GenerateServiceRequestFingerprint.Request();
        request.authorizedAssetId = '02i000000000001AAA';
        request.originalServiceRequest = '   ';

        Test.startTest();
        List<GenerateServiceRequestFingerprint.Result> results =
            GenerateServiceRequestFingerprint.generate(new List<GenerateServiceRequestFingerprint.Request>{request});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assertEquals('MISSING_REQUIRED_INPUT', results[0].statusCode);
        System.assertEquals(null, results[0].fingerprint);
    }


    @IsTest
    static void nullRequestListReturnsEmptyResults() {
        Test.startTest();
        List<GenerateServiceRequestFingerprint.Result> results = GenerateServiceRequestFingerprint.generate(null);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Method should return an empty list rather than null.');
        System.assertEquals(0, results.size(), 'Null request collection should produce no results.');
    }


    @IsTest
    static void bulkRequestsAreProcessedIndependently() {
        GenerateServiceRequestFingerprint.Request validOne = new GenerateServiceRequestFingerprint.Request();
        validOne.authorizedAssetId = '02i000000000001AAA';
        validOne.originalServiceRequest = 'Machine is making a clicking noise.';

        GenerateServiceRequestFingerprint.Request invalid = new GenerateServiceRequestFingerprint.Request();
        invalid.authorizedAssetId = '02i000000000001AAA';
        invalid.originalServiceRequest = null;

        GenerateServiceRequestFingerprint.Request validTwo = new GenerateServiceRequestFingerprint.Request();
        validTwo.authorizedAssetId = '02i000000000002AAA';
        validTwo.originalServiceRequest = 'Machine is leaking coolant.';


        Test.startTest();
        List<GenerateServiceRequestFingerprint.Result> results =
            GenerateServiceRequestFingerprint.generate(new List<GenerateServiceRequestFingerprint.Request>{validOne, invalid, validTwo});
        Test.stopTest();

        System.assertEquals(3, results.size(), 'Each input should produce a corresponding output.');

        System.assertEquals(true, results[0].success);
        System.assertEquals('FINGERPRINT_CREATED', results[0].statusCode);
        System.assertNotEquals(null, results[0].fingerprint);

        System.assertEquals(false, results[1].success);
        System.assertEquals('MISSING_REQUIRED_INPUT', results[1].statusCode);
        System.assertEquals(null, results[1].fingerprint);

        System.assertEquals(true, results[2].success);
        System.assertEquals('FINGERPRINT_CREATED', results[2].statusCode);
        System.assertNotEquals(null, results[2].fingerprint);
    }
}