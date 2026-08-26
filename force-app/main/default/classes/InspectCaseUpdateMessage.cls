public with sharing class InspectCaseUpdateMessage {

    public class Request {
        @InvocableVariable(required=true)
        public String customerMessage;
    }

    public class Response {
        @InvocableVariable
        public String route;

        @InvocableVariable
        public String requestedCaseNumber;
    }

    @InvocableMethod(
        label='Inspect Case Update Message'
        description='Deterministically classifies a customer Case message before Case authorization, status lookup, or comment creation.'
    )
    public static List<Response> inspectMessages(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request request : requests) {
            Response response = new Response();

            String originalMessage =
                request == null
                ? null
                : request.customerMessage;

            String trimmedMessage = String.isBlank(originalMessage) ? '' : originalMessage.trim();

            String normalizedMessage = trimmedMessage.toLowerCase();

            /*
             * 1. Blank message
             */
            if (String.isBlank(trimmedMessage)) {
                response.route = 'REQUEST_UPDATE_TEXT';
                response.requestedCaseNumber = null;
                responses.add(response);
                continue;
            }

            /*
             * Normalize punctuation for deterministic intent checks.
             */
            String normalizedIntent =
                normalizedMessage
                    .replace('?', '')
                    .replace('.', '')
                    .replace('!', '')
                    .replace(',', '')
                    .trim();

            /*
             * Determine UPDATE / STATUS intent before Case Number extraction
             * so intent can be preserved even when the customer supplies an
             * unusable selector such as a Salesforce record ID.
             */
            Boolean hasUpdateIntent =
                normalizedMessage.contains('update') ||
                normalizedMessage.contains('add something') ||
                normalizedMessage.contains('add information') ||
                normalizedMessage.contains('add another') ||
                normalizedMessage.contains('add a detail') ||
                normalizedMessage.contains('add another detail') ||
                normalizedMessage.contains('more information') ||
                normalizedMessage.contains('another detail') ||
                normalizedMessage.contains('append') ||
                normalizedMessage.contains('note down') ||
                normalizedMessage.contains('make a note');

            Boolean hasStatusIntent =
                normalizedMessage.contains('status') ||
                normalizedMessage.contains('still open') ||
                normalizedMessage.contains('is it open') ||
                normalizedMessage.contains('is this open') ||
                normalizedMessage.contains('is the case open') ||
                normalizedMessage.contains('is case ') ||
                normalizedMessage.contains('can you check') ||
                normalizedMessage.contains('check case') ||
                normalizedMessage.contains('check the case') ||
                normalizedMessage.contains('check service request') ||
                normalizedMessage.contains('check the service request') ||
                normalizedMessage.contains('what is happening with') ||
                normalizedMessage.contains('what\'s happening with');

            /*
             * 2. Look for an explicitly supplied customer-visible
             *    Case Number.
             *
             * Supported examples:
             *
             * "Case 00001153"
             * "Case Number 00001153"
             * "Case #00001153"
             * "service request 00001153"
             * "service request #00001153"
             *
             * Preserve leading zeroes exactly.
             */
            String explicitCaseNumber = null;

            Pattern caseReferencePattern = Pattern.compile('(?i)\\bcase\\s*(?:number\\s*)?#?\\s*([0-9]{4,12})\\b');

            Matcher caseReferenceMatcher = caseReferencePattern.matcher(trimmedMessage);

            if (caseReferenceMatcher.find()) {
                explicitCaseNumber = caseReferenceMatcher.group(1);
            }

            /*
             * If "Case" was not used, also support the customer-facing
             * phrase "service request".
             */
            if (explicitCaseNumber == null) {
                Pattern serviceRequestPattern = Pattern.compile('(?i)\\bservice\\s+request\\s*(?:number\\s*)?#?\\s*([0-9]{4,12})\\b');

                Matcher serviceRequestMatcher = serviceRequestPattern.matcher(trimmedMessage);

                if (serviceRequestMatcher.find()) {
                    explicitCaseNumber = serviceRequestMatcher.group(1);
                }
            }

            /*
             * 3. Explicit Case Number:
             *    determine whether this is an UPDATE or STATUS request.
             *
             * UPDATE takes priority when both kinds of wording appear,
             * because the customer is explicitly asking to modify the Case.
             */
            if (explicitCaseNumber != null) {

                /*
                 * Examples:
                 *
                 * "I want to update Case 00001153"
                 * "I want to add something to Case 00001153"
                 *
                 * → RESOLVE_CASE
                 */
                if (hasUpdateIntent) {
                    response.route = 'RESOLVE_CASE';
                    response.requestedCaseNumber = explicitCaseNumber;

                    responses.add(response);
                    continue;
                }

                /*
                 * Examples:
                 *
                 * "What is the status of Case 00001153?"
                 * "Is Case 00001153 still open?"
                 * "Can you check Case 00001153?"
                 * "What is happening with service request 00001153?"
                 *
                 * → STATUS_CASE
                 */
                if (hasStatusIntent) {
                    response.route = 'STATUS_CASE';
                    response.requestedCaseNumber = explicitCaseNumber;

                    responses.add(response);
                    continue;
                }

                /*
                 * An explicit Case Number without clear STATUS language
                 * continues to behave as an UPDATE selector.
                 *
                 * This preserves the existing Case-update workflow.
                 */
                response.route = 'RESOLVE_CASE';
                response.requestedCaseNumber = explicitCaseNumber;

                responses.add(response);
                continue;
            }

            /*
             * 4. STATUS intent without a usable customer-visible Case Number.
             *
             * Examples:
             * "Can you check the status of this service request?"
             * "Can you check the status of this service request? 500gK00001Hw386QAB"
             *
             * A Salesforce record ID is intentionally not accepted as a Case
             * Number. Preserve the STATUS intent and ask for the customer-visible
             * Case Number instead of falling through to SAVE_UPDATE.
             */
            if (hasStatusIntent && !hasUpdateIntent) {
                response.route = 'REQUEST_STATUS_CASE_NUMBER';
                response.requestedCaseNumber = null;
                responses.add(response);
                continue;
            }

            /*
             * 5. Bare Case Number response.
             *
             * Useful after:
             * "What Case Number would you like to update?"
             *
             * Example:
             * "00001153"
             *
             * A bare number remains an UPDATE selector because this
             * Apex action is used while a Case-update selector may
             * already be pending.
             *
             * Salesforce record IDs are not numeric-only and therefore
             * cannot match this pattern.
             */
            Pattern bareCaseNumberPattern = Pattern.compile('^([0-9]{4,12})$');

            Matcher bareCaseNumberMatcher = bareCaseNumberPattern.matcher(trimmedMessage);

            if (bareCaseNumberMatcher.matches()) {
                response.route = 'RESOLVE_CASE';
                response.requestedCaseNumber = bareCaseNumberMatcher.group(1);

                responses.add(response);
                continue;
            }

            /*
             * 6. Customer explicitly wants another/different/other Case
             *    but did not provide the Case Number.
             */
            Boolean requestsDifferentCase =
                normalizedMessage.contains('different case') ||
                normalizedMessage.contains('another case') ||
                normalizedMessage.contains('other case') ||
                normalizedMessage.contains('different service request') ||
                normalizedMessage.contains('another service request') ||
                normalizedMessage.contains('other service request');

            if (requestsDifferentCase) {
                response.route = 'REQUEST_CASE_NUMBER';
                response.requestedCaseNumber = null;
                responses.add(response);
                continue;
            }

            /*
             * 7. Customer expresses only the intent to update the
             *    current Case but has not supplied the actual update yet.
             */
            Set<String> updateIntentOnlyMessages = new Set<String>{
                'i want to update the case',
                'i want to update this case',
                'i want to update my case',
                'i want to add something to the case',
                'i want to add something to this case',
                'i want to add something to my case',
                'i need to update the case',
                'i need to update this case',
                'i need to update my case',
                'i need to add something to the case',
                'i need to add something to this case',
                'i need to add something to my case',
                'can i update the case',
                'can i update this case',
                'can i update my case',
                'can i add something to the case',
                'can i add something to this case',
                'can i add something to my case',
                'i want to update the service request',
                'i want to update this service request',
                'i want to update my service request',
                'i want to add something to the service request',
                'i want to add something to this service request',
                'i want to add something to my service request'
            };

            if (updateIntentOnlyMessages.contains(normalizedIntent)) {
                response.route = 'REQUEST_UPDATE_TEXT';
                response.requestedCaseNumber = null;
                responses.add(response);
                continue;
            }

            /*
             * 8. Everything else is substantive information intended
             *    for the already-authorized current Case.
             *
             * Examples:
             *
             * "The chamber light is flickering constantly now."
             * "The disc changer makes a grinding noise when it moves."
             */
            response.route = 'SAVE_UPDATE';
            response.requestedCaseNumber = null;

            responses.add(response);
        }

        return responses;
    }
}