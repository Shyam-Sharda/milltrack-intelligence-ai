public with sharing class GenerateServiceRequestFingerprint {

    public class Request {
        @InvocableVariable(
            label='Authorized Asset ID'
            description='Trusted authorized Asset ID for the customer service request.'
            required=true
        )
        public String authorizedAssetId;

        @InvocableVariable(
            label='Original Service Request'
            description='Original customer service request preserved before any AI-generated Subject or Description.'
            required=true
        )
        public String originalServiceRequest;
    }

    public class Result {
        @InvocableVariable(
            label='Fingerprint'
            description='Deterministic SHA-256 fingerprint for duplicate open Case detection.'
        )
        public String fingerprint;

        @InvocableVariable(
            label='Success'
            description='True when a fingerprint was generated successfully.'
        )
        public Boolean success;

        @InvocableVariable(
            label='Status Code'
            description='FINGERPRINT_CREATED or MISSING_REQUIRED_INPUT.'
        )
        public String statusCode;
    }

    @InvocableMethod(
        label='Generate Service Request Fingerprint'
        description='Generates a deterministic SHA-256 fingerprint from the trusted authorized Asset ID and original customer service request for duplicate open Case detection.'
    )
    public static List<Result> generate(List<Request> requests) {

        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }

        for (Request input : requests) {
            Result output = new Result();
            output.success = false;
            output.statusCode = 'MISSING_REQUIRED_INPUT';
            output.fingerprint = null;

            if (input == null || String.isBlank(input.authorizedAssetId) || String.isBlank(input.originalServiceRequest)) {
                results.add(output);
                continue;
            }

            String normalizedAssetId = input.authorizedAssetId.trim().toLowerCase();

            String normalizedRequest = input.originalServiceRequest.trim().toLowerCase();

            // Normalize formatting differences without changing the substantive content of the customer's request.
            normalizedRequest = normalizedRequest.replaceAll('\\s+', ' ');

            // Version the fingerprint format so its construction is explicit and can be evolved intentionally in the future.
            String fingerprintSource = 'v1|asset=' + normalizedAssetId + '|request=' + normalizedRequest;

            Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(fingerprintSource));

            output.fingerprint = EncodingUtil.convertToHex(digest).toLowerCase();

            output.success = true;
            output.statusCode = 'FINGERPRINT_CREATED';

            results.add(output);
        }

        return results;
    }
}