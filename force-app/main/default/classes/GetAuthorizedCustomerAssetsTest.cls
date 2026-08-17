@IsTest
private class GetAuthorizedCustomerAssetsTest {
    @TestSetup
    static void createTestData() {
        Account accountA = new Account(Name = 'MillTrack Test Dental Lab A');
        Account accountB = new Account(Name = 'MillTrack Test Dental Lab B');
        insert new List<Account>{ accountA, accountB };

        Contact contactA = new Contact(
            FirstName = 'Customer',
            LastName = 'Tester A',
            AccountId = accountA.Id,
            Email = 'customer-a@example.test'
        );
        Contact contactB = new Contact(
            FirstName = 'Customer',
            LastName = 'Tester B',
            AccountId = accountB.Id,
            Email = 'customer-b@example.test'
        );
        insert new List<Contact>{ contactA, contactB };

        Asset assetA = new Asset(
            Name = 'Lab A Mill',
            AccountId = accountA.Id,
            ContactId = contactA.Id,
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-52D',
            Serial_Number__c = 'ROLAND-A-1234'
        );
        Asset assetB = new Asset(
            Name = 'Lab B Mill',
            AccountId = accountB.Id,
            ContactId = contactB.Id,
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-42W',
            Serial_Number__c = 'ROLAND-B-9876'
        );
        insert new List<Asset>{ assetA, assetB };
    }

    @IsTest
    static void returnsOnlyAssetsForVerifiedContactsAccount() {
        Contact contactA = [
            SELECT Id
            FROM Contact
            WHERE Email = 'customer-a@example.test'
            LIMIT 1
        ];
        Asset assetA = [
            SELECT Id
            FROM Asset
            WHERE Name = 'Lab A Mill'
            LIMIT 1
        ];

        GetAuthorizedCustomerAssetsController.Request requestValue = new GetAuthorizedCustomerAssetsController.Request();
        requestValue.verifiedCustomerId = String.valueOf(contactA.Id);

        Test.startTest();
        List<GetAuthorizedCustomerAssetsController.Response> results =
            GetAuthorizedCustomerAssetsController.getAuthorizedCustomerAssets(new List<GetAuthorizedCustomerAssetsController.Request>{ requestValue });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals('SUCCESS', results[0].statusCode);
        System.assertEquals(1, results[0].assetCount);
        System.assert(results[0].assetOptions.contains('Lab A Mill'));
        System.assert(results[0].assetOptions.contains('1234'));
        System.assertEquals(false, results[0].assetOptions.contains('Lab B Mill'));
        System.assertEquals(false, results[0].assetOptions.contains('9876'));
        System.assert(results[0].authorizedAssetReferences.contains('1=' + String.valueOf(assetA.Id)));
    }

    @IsTest
    static void returnsNoAssetsForAuthorizedAccountWithoutMachines() {
        Account accountC = new Account(Name = 'MillTrack Test Dental Lab C');
        insert accountC;

        Contact contactC = new Contact(
            FirstName = 'Customer',
            LastName = 'Tester C',
            AccountId = accountC.Id,
            Email = 'customer-c@example.test'
        );
        insert contactC;

        GetAuthorizedCustomerAssetsController.Request requestValue = new GetAuthorizedCustomerAssetsController.Request();
        requestValue.verifiedCustomerId = String.valueOf(contactC.Id);

        Test.startTest();
        List<GetAuthorizedCustomerAssetsController.Response> results =
            GetAuthorizedCustomerAssetsController.getAuthorizedCustomerAssets(new List<GetAuthorizedCustomerAssetsController.Request>{ requestValue });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assertEquals('NO_ASSETS', results[0].statusCode);
        System.assertEquals(0, results[0].assetCount);
        System.assertEquals('', results[0].authorizedAssetReferences);
    }

    @IsTest
    static void rejectsUnverifiedAndNonCustomerIdentifiers() {
        Account accountA = [
            SELECT Id
            FROM Account
            WHERE Name = 'MillTrack Test Dental Lab A'
            LIMIT 1
        ];

        List<GetAuthorizedCustomerAssetsController.Request> requests = new List<GetAuthorizedCustomerAssetsController.Request>();

        GetAuthorizedCustomerAssetsController.Request blankRequest = new GetAuthorizedCustomerAssetsController.Request();
        blankRequest.verifiedCustomerId = '';
        requests.add(blankRequest);

        GetAuthorizedCustomerAssetsController.Request malformedRequest = new GetAuthorizedCustomerAssetsController.Request();
        malformedRequest.verifiedCustomerId = 'not-a-salesforce-id';
        requests.add(malformedRequest);

        GetAuthorizedCustomerAssetsController.Request accountRequest = new GetAuthorizedCustomerAssetsController.Request();
        accountRequest.verifiedCustomerId = String.valueOf(accountA.Id);
        requests.add(accountRequest);

        Test.startTest();
        List<GetAuthorizedCustomerAssetsController.Response> results = GetAuthorizedCustomerAssetsController.getAuthorizedCustomerAssets(requests);
        Test.stopTest();

        System.assertEquals(3, results.size());
        for (GetAuthorizedCustomerAssetsController.Response resultValue : results) {
            System.assertEquals(false, resultValue.success);
            System.assertEquals('INVALID_VERIFIED_CUSTOMER', resultValue.statusCode);
            System.assertEquals(0, resultValue.assetCount);
        }
    }
}