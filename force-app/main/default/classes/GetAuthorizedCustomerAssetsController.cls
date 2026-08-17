public with sharing class GetAuthorizedCustomerAssetsController {
    private static final Integer MAX_ASSETS_PER_CUSTOMER = 50;

    public class Request {
        @InvocableVariable(
            required=true
            label='Verified Customer ID'
            description='Credential-verified Agentforce customer context ID. Map this input from VerifiedCustomerId. Never collect it from the customer.'
        )
        public String verifiedCustomerId;
    }

    public class Response {
        @InvocableVariable(
            label='Success'
            description='True only when the verified customer was resolved and the Asset lookup completed successfully.'
        )
        public Boolean success;

        @InvocableVariable(
            label='Status Code'
            description='Machine-readable result: SUCCESS, NO_ASSETS, INVALID_VERIFIED_CUSTOMER, or ERROR.'
        )
        public String statusCode;

        @InvocableVariable(
            label='Customer Message'
            description='Customer-safe explanation of the lookup result.'
        )
        public String customerMessage;

        @InvocableVariable(
            label='Asset Count'
            description='Number of authorized Assets returned for the verified customer.'
        )
        public Integer assetCount;

        @InvocableVariable(
            label='Customer-Safe Asset Options'
            description='Customer-visible authorized machine choices containing Asset Name, Manufacturer, Model, Machine Serial Number, and Machine Status. May be displayed verbatim to the verified customer. Does not contain Salesforce record IDs.'
        )
        public String assetOptions;

        @InvocableVariable(
            label='Authorized Asset References'
            description='Internal option-to-Asset-ID mapping for later authorized actions. Do not show this output in the conversation.'
        )
        public String authorizedAssetReferences;
    }

    @InvocableMethod(
        label='Get Authorized Customer Assets'
        description='Returns only dental milling equipment Assets belonging to the Account associated with the credential-verified Experience Cloud customer.'
    )
    public static List<Response> getAuthorizedCustomerAssets(
        List<Request> requests
    ) {
        List<Response> responses = new List<Response>();

        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        Set<Id> requestedUserIds = new Set<Id>();
        Set<Id> requestedContactIds = new Set<Id>();
        Map<Integer, Id> validInputIdsByIndex = new Map<Integer, Id>();
        Map<Integer, String> inputTypesByIndex =
            new Map<Integer, String>();

        for (Integer i = 0; i < requests.size(); i++) {
            String rawId = requests[i] == null
                ? null
                : requests[i].verifiedCustomerId;

            Id verifiedId = parseSalesforceId(rawId);

            if (verifiedId == null) {
                continue;
            }

            Schema.SObjectType inputType =
                verifiedId.getSObjectType();

            if (inputType == User.SObjectType) {
                requestedUserIds.add(verifiedId);
                validInputIdsByIndex.put(i, verifiedId);
                inputTypesByIndex.put(i, 'User');
            } else if (inputType == Contact.SObjectType) {
                requestedContactIds.add(verifiedId);
                validInputIdsByIndex.put(i, verifiedId);
                inputTypesByIndex.put(i, 'Contact');
            }
        }

        try {
            Map<Id, User> usersById = new Map<Id, User>();

            if (!requestedUserIds.isEmpty()) {
                usersById = new Map<Id, User>([
                    SELECT Id, ContactId
                    FROM User
                    WHERE Id IN :requestedUserIds
                    WITH USER_MODE
                ]);

                for (User portalUser : usersById.values()) {
                    if (portalUser.ContactId != null) {
                        requestedContactIds.add(
                            portalUser.ContactId
                        );
                    }
                }
            }

            Map<Id, Contact> contactsById =
                new Map<Id, Contact>();

            if (!requestedContactIds.isEmpty()) {
                contactsById = new Map<Id, Contact>([
                    SELECT Id, AccountId
                    FROM Contact
                    WHERE Id IN :requestedContactIds
                    WITH USER_MODE
                ]);
            }

            Map<Integer, Id> contactIdsByIndex =
                new Map<Integer, Id>();

            Set<Id> authorizedAccountIds = new Set<Id>();

            for (Integer i = 0; i < requests.size(); i++) {
                Id verifiedId = validInputIdsByIndex.get(i);
                String inputType = inputTypesByIndex.get(i);
                Id contactId;

                if (inputType == 'Contact') {
                    contactId = verifiedId;
                } else if (
                    inputType == 'User' &&
                    usersById.containsKey(verifiedId)
                ) {
                    contactId =
                        usersById.get(verifiedId).ContactId;
                }

                if (
                    contactId != null &&
                    contactsById.containsKey(contactId)
                ) {
                    Contact customerContact =
                        contactsById.get(contactId);

                    if (customerContact.AccountId != null) {
                        contactIdsByIndex.put(i, contactId);
                        authorizedAccountIds.add(
                            customerContact.AccountId
                        );
                    }
                }
            }

            Map<Id, List<Asset>> assetsByAccountId =
                new Map<Id, List<Asset>>();

            if (!authorizedAccountIds.isEmpty()) {
                for (Asset machine : [
                    SELECT Id,
                           AccountId,
                           Name,
                           Manufacturer__c,
                           Model__c,
                           Serial_Number__c,
                           Machine_Status__c
                    FROM Asset
                    WHERE AccountId IN :authorizedAccountIds
                    WITH USER_MODE
                    ORDER BY Name, Id
                    LIMIT 2000
                ]) {
                    if (
                        !assetsByAccountId.containsKey(
                            machine.AccountId
                        )
                    ) {
                        assetsByAccountId.put(
                            machine.AccountId,
                            new List<Asset>()
                        );
                    }

                    List<Asset> accountAssets =
                        assetsByAccountId.get(
                            machine.AccountId
                        );

                    if (
                        accountAssets.size() <
                        MAX_ASSETS_PER_CUSTOMER
                    ) {
                        accountAssets.add(machine);
                    }
                }
            }

            for (Integer i = 0; i < requests.size(); i++) {
                Id contactId = contactIdsByIndex.get(i);

                if (
                    contactId == null ||
                    !contactsById.containsKey(contactId)
                ) {
                    responses.add(
                        invalidCustomerResponse()
                    );
                    continue;
                }

                Id accountId =
                    contactsById.get(contactId).AccountId;

                List<Asset> authorizedAssets =
                    assetsByAccountId.get(accountId);

                if (
                    authorizedAssets == null ||
                    authorizedAssets.isEmpty()
                ) {
                    responses.add(noAssetsResponse());
                    continue;
                }

                responses.add(
                    successResponse(authorizedAssets)
                );
            }
        } catch (Exception exceptionValue) {
            // Return a customer-safe failure without exposing
            // implementation details or Salesforce record data.
            responses.clear();

            for (
                Integer i = 0;
                i < requests.size();
                i++
            ) {
                responses.add(errorResponse());
            }
        }

        return responses;
    }

    private static Id parseSalesforceId(String rawId) {
        if (String.isBlank(rawId)) {
            return null;
        }

        try {
            return (Id) rawId.trim();
        } catch (Exception exceptionValue) {
            return null;
        }
    }

    private static Response successResponse(
        List<Asset> assets
    ) {
        Response response = baseResponse();

        response.success = true;
        response.statusCode = 'SUCCESS';
        response.assetCount = assets.size();

        response.customerMessage =
            assets.size() == 1
                ? 'One authorized machine was found. Ask the customer to confirm it.'
                : String.valueOf(assets.size()) +
                  ' authorized machines were found. Ask the customer to select one.';

        List<String> options = new List<String>();
        List<String> references = new List<String>();
        Integer optionNumber = 1;

        for (Asset machine : assets) {
            String serialValue =
                machine.Serial_Number__c;

            List<String> details = new List<String>{
                String.valueOf(optionNumber) + '.',
                sanitize(machine.Name),
                'Manufacturer: ' +
                    valueOrUnavailable(
                        machine.Manufacturer__c
                    ),
                'Model: ' +
                    valueOrUnavailable(
                        machine.Model__c
                    ),
                'Serial: ' +
                    valueOrUnavailable(serialValue),
                'Status: ' +
                    valueOrUnavailable(
                        machine.Machine_Status__c
                    )
            };

            options.add(
                String.join(details, ' | ')
            );

            references.add(
                String.valueOf(optionNumber) +
                '=' +
                String.valueOf(machine.Id)
            );

            optionNumber++;
        }

        response.assetOptions =
            String.join(options, '\n');

        response.authorizedAssetReferences =
            String.join(references, ';');

        return response;
    }

    private static Response invalidCustomerResponse() {
        Response response = baseResponse();

        response.statusCode =
            'INVALID_VERIFIED_CUSTOMER';

        response.customerMessage =
            'Your verified customer profile could not be connected to a MillTrack customer account. Please request service assistance.';

        return response;
    }

    private static Response noAssetsResponse() {
        Response response = baseResponse();

        response.statusCode = 'NO_ASSETS';

        response.customerMessage =
            'No equipment is currently available through your verified MillTrack account. Please request service assistance if this appears incorrect.';

        return response;
    }

    private static Response errorResponse() {
        Response response = baseResponse();

        response.statusCode = 'ERROR';

        response.customerMessage =
            'Authorized equipment information could not be retrieved right now. Please try again or request service assistance.';

        return response;
    }

    private static Response baseResponse() {
        Response response = new Response();

        response.success = false;
        response.assetCount = 0;
        response.assetOptions = '';
        response.authorizedAssetReferences = '';

        return response;
    }

    private static String valueOrUnavailable(
        String value
    ) {
        return String.isBlank(value)
            ? 'Not available'
            : sanitize(value);
    }

    private static String sanitize(String value) {
        if (String.isBlank(value)) {
            return 'Not available';
        }

        String cleaned = value
            .replace('\r', ' ')
            .replace('\n', ' ')
            .replace('|', '/')
            .replace(';', ',');

        return cleaned.length() <= 120
            ? cleaned
            : cleaned.substring(0, 120);
    }
}