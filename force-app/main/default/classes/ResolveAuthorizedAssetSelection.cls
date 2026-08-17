public with sharing class ResolveAuthorizedAssetSelection {

    public class Request {
        @InvocableVariable(
            required=true
            label='Authorized Asset References'
            description='Internal numbered mapping returned by Get Authorized Customer Assets. Never collect this value from the customer.'
        )
        public String authorizedAssetReferences;

        /*
         * Legacy input retained temporarily for backward compatibility
         * with existing Agentforce versions.
         *
         * New Agent Script versions should use selectedOptionText instead.
         */
        @InvocableVariable(
            required=false
            label='Selected Option Number'
            description='Legacy numbered authorized machine option. New implementations should use Selected Option Text.'
        )
        public Integer selectedOptionNumber;

        @InvocableVariable(
            required=false
            label='Selected Option Text'
            description='Raw customer reply used to select a previously displayed authorized machine option. Accepts an exact positive option number, or a simple positive confirmation when exactly one authorized machine exists.'
        )
        public String selectedOptionText;
    }

    public class Response {
        @InvocableVariable(
            label='Success'
            description='True only when the customer selection maps to a valid authorized Asset reference.'
        )
        public Boolean success;

        @InvocableVariable(
            label='Status Code'
            description='Machine-readable result: CONFIRMED, INVALID_SELECTION, MISSING_AUTHORIZED_REFERENCES, or ERROR.'
        )
        public String statusCode;

        @InvocableVariable(
            label='Confirmed Asset ID'
            description='Internal Asset ID corresponding to the authorized machine selected by the customer. Never display this value.'
        )
        public String confirmedAssetId;

        @InvocableVariable(
            label='Customer Message'
            description='Customer-safe explanation of the confirmation result.'
        )
        public String customerMessage;
    }

    @InvocableMethod(
        label='Resolve Authorized Asset Selection'
        description='Safely resolves a customer reply to an Asset ID previously returned by Get Authorized Customer Assets. The customer reply never independently authorizes an Asset.'
    )
    public static List<Response> resolveSelections(List<Request> requests) {

        List<Response> responses = new List<Response>();

        if (requests == null) {
            return responses;
        }

        for (Request request : requests) {
            try {
                responses.add(resolveSingle(request));
            } catch (Exception ex) {
                responses.add(errorResponse());
            }
        }

        return responses;
    }

    private static Response resolveSingle(Request request) {

        if (request == null || String.isBlank(request.authorizedAssetReferences)) {
            return missingReferencesResponse();
        }

        Map<Integer, Id> authorizedAssetsByOption = parseAuthorizedReferences(request.authorizedAssetReferences);

        if (authorizedAssetsByOption.isEmpty()) {
            return missingReferencesResponse();
        }

        Integer selectedOption = resolveSelectedOption(request, authorizedAssetsByOption);

        if (
            selectedOption == null || selectedOption <= 0 || !authorizedAssetsByOption.containsKey(selectedOption)
        ) {
            return invalidSelectionResponse();
        }

        Id selectedAssetId = authorizedAssetsByOption.get(selectedOption);

        if (
            selectedAssetId == null ||
            selectedAssetId.getSObjectType() != Asset.SObjectType
        ) {
            return invalidSelectionResponse();
        }

        Response response = baseResponse();
        response.success = true;
        response.statusCode = 'CONFIRMED';
        response.confirmedAssetId = String.valueOf(selectedAssetId);
        response.customerMessage = 'The selected machine was confirmed.';
        return response;
    }

    /*
     * Resolves the customer's selected option without allowing the model
     * or customer to provide a raw Asset ID.
     *
     * Resolution order:
     * 1. Legacy Integer input, if supplied.
     * 2. Exact numeric customer reply such as "1" or "2".
     * 3. Simple positive confirmation when exactly one authorized Asset exists.
     */
    private static Integer resolveSelectedOption(Request request, Map<Integer, Id> authorizedAssetsByOption) {

        /*
         * Backward compatibility for currently active Agentforce versions.
         */
        if (
            request.selectedOptionNumber != null && request.selectedOptionNumber > 0
        ) {
            return request.selectedOptionNumber;
        }

        if (String.isBlank(request.selectedOptionText)) {
            return null;
        }

        String trimmedSelection = request.selectedOptionText.trim();

        /*
         * Multiple-Asset selection:
         * Accept only an exact positive integer.
         *
         * Examples accepted:
         * "1"
         * "2"
         *
         * Raw Salesforce IDs or arbitrary text are never interpreted
         * as authorization.
         */
        if (Pattern.matches('^[0-9]+$', trimmedSelection)) {
            try {
                Integer parsedOption = Integer.valueOf(trimmedSelection);

                if (parsedOption > 0) {
                    return parsedOption;
                }
            } catch (Exception ex) {
                return null;
            }
        }

        /*
         * Single-Asset confirmation:
         * A simple positive response may safely resolve to option 1
         * only because the trusted authorized reference map contains
         * exactly one Asset.
         */
        if (authorizedAssetsByOption.size() == 1) {

            String normalizedSelection = trimmedSelection.toLowerCase();

            Set<String> positiveConfirmations = new Set<String>{
                'yes',
                'yes it is',
                'yes that is it',
                'yes thats it',
                'yes that\'s it',
                'that one',
                'this one',
                'correct',
                'yep',
                'yeah'
            };

            if (positiveConfirmations.contains(normalizedSelection)) {
                for (Integer optionNumber : authorizedAssetsByOption.keySet()) {
                    return optionNumber;
                }
            }
        }

        return null;
    }

    private static Map<Integer, Id> parseAuthorizedReferences(String rawReferences) {
        Map<Integer, Id> result = new Map<Integer, Id>();

        for (String referenceEntry : rawReferences.split(';')) {

            if (String.isBlank(referenceEntry)) {
                continue;
            }

            List<String> parts = referenceEntry.split('=');

            if (parts.size() != 2) {
                continue;
            }

            Integer optionNumber;

            try {
                optionNumber = Integer.valueOf(parts[0].trim());
            } catch (Exception ex) {
                continue;
            }

            Id assetId;

            try {
                assetId = (Id) parts[1].trim();
            } catch (Exception ex) {
                continue;
            }

            if (
                optionNumber > 0 &&
                assetId != null &&
                assetId.getSObjectType() == Asset.SObjectType
            ) {
                result.put(optionNumber, assetId);
            }
        }

        return result;
    }

    private static Response baseResponse() {
        Response response = new Response();
        response.success = false;
        response.statusCode = '';
        response.confirmedAssetId = '';
        response.customerMessage = '';
        return response;
    }

    private static Response missingReferencesResponse() {
        Response response = baseResponse();
        response.statusCode = 'MISSING_AUTHORIZED_REFERENCES';
        response.customerMessage = 'The authorized machine information is no longer available. Please identify the machine again.';
        return response;
    }

    private static Response invalidSelectionResponse() {
        Response response = baseResponse();
        response.statusCode = 'INVALID_SELECTION';
        response.customerMessage = 'I could not match that selection to an authorized machine.';
        return response;
    }

    private static Response errorResponse() {
        Response response = baseResponse();
        response.statusCode = 'ERROR';
        response.customerMessage = 'The machine selection could not be confirmed right now.';
        return response;
    }
}