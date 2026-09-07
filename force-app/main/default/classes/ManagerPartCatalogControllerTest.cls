@IsTest
private class ManagerPartCatalogControllerTest {

    // =========================================================
    // TEST SETUP
    // =========================================================

    @TestSetup
    static void createCatalogData() {

        List<Part_Catalog__c> catalogParts =
            new List<Part_Catalog__c>{

                new Part_Catalog__c(
                    Name = 'Alpha Spindle Bearing',
                    Part_Number__c = 'MPC-TEST-001',
                    Manufacturer__c = 'Roland',
                    Compatible_Model__c = 'DWX-52D',
                    Parts_Category__c = 'Spindle',
                    Supplier_Name__c = 'Supplier Alpha',
                    Supplier_Phone__c = '555-300-0001',
                    Order_URL__c =
                        'https://example.com/alpha-spindle',
                    Active__c = true,
                    Keyword_Aliases__c =
                        'spindle bearing bearings'
                ),

                new Part_Catalog__c(
                    Name = 'Beta Coolant Filter',
                    Part_Number__c = 'MPC-TEST-002',
                    Manufacturer__c = 'Roland',
                    Compatible_Model__c =
                        'DWX-52D; DWX-53DC',
                    Parts_Category__c = 'Coolant System',
                    Supplier_Name__c = 'Supplier Beta',
                    Supplier_Phone__c = '555-300-0002',
                    Order_URL__c =
                        'https://example.com/beta-coolant',
                    Active__c = true,
                    Keyword_Aliases__c =
                        'coolant filter filtration'
                ),

                new Part_Catalog__c(
                    Name = 'Gamma Door Sensor',
                    Part_Number__c = 'MPC-TEST-003',
                    Manufacturer__c = 'Roland',
                    Compatible_Model__c = 'DWX-53DC',
                    Parts_Category__c =
                        'Calibration & Sensors',
                    Supplier_Name__c = 'Supplier Gamma',
                    Supplier_Phone__c = '555-300-0003',
                    Order_URL__c =
                        'https://example.com/gamma-sensor',
                    Active__c = true,
                    Keyword_Aliases__c =
                        'door sensor switch calibration'
                ),

                /*
                 * This record has the correct manufacturer,
                 * but it is inactive and must never be returned.
                 */
                new Part_Catalog__c(
                    Name = 'Inactive Spindle Assembly',
                    Part_Number__c = 'MPC-TEST-004',
                    Manufacturer__c = 'Roland',
                    Compatible_Model__c = 'DWX-52D',
                    Parts_Category__c = 'Spindle',
                    Supplier_Name__c = 'Supplier Inactive',
                    Supplier_Phone__c = '555-300-0004',
                    Order_URL__c =
                        'https://example.com/inactive',
                    Active__c = false,
                    Keyword_Aliases__c =
                        'inactive spindle'
                )
            };

        insert catalogParts;
    }

    // =========================================================
    // BLANK MANUFACTURER
    // =========================================================

    @IsTest
    static void getCompatiblePartsReturnsEmptyForBlankManufacturer() {

        Test.startTest();

        List<ManagerPartCatalogController.PartOption> nullResults =
            ManagerPartCatalogController.getCompatibleParts(
                null,
                'DWX-52D'
            );

        List<ManagerPartCatalogController.PartOption> blankResults =
            ManagerPartCatalogController.getCompatibleParts(
                '   ',
                'DWX-52D'
            );

        Test.stopTest();

        System.assertEquals(
            0,
            nullResults.size(),
            'A null manufacturer should return no parts.'
        );

        System.assertEquals(
            0,
            blankResults.size(),
            'A blank manufacturer should return no parts.'
        );
    }

    // =========================================================
    // ACTIVE MANUFACTURER FILTERING
    // =========================================================

    @IsTest
    static void getCompatiblePartsReturnsOnlyActiveManufacturerParts() {

        Test.startTest();

        List<ManagerPartCatalogController.PartOption> results =
            ManagerPartCatalogController.getCompatibleParts(
                'Roland',
                'DWX-52D'
            );

        Test.stopTest();

        System.assertEquals(
            3,
            results.size(),
            'Only the three active Roland catalog parts should be returned.'
        );

        Set<String> returnedPartNumbers =
            new Set<String>();

        for (
            ManagerPartCatalogController.PartOption option :
            results
        ) {
            returnedPartNumbers.add(
                option.partNumber
            );
        }

        System.assertEquals(
            true,
            returnedPartNumbers.contains(
                'MPC-TEST-001'
            )
        );

        System.assertEquals(
            true,
            returnedPartNumbers.contains(
                'MPC-TEST-002'
            )
        );

        System.assertEquals(
            true,
            returnedPartNumbers.contains(
                'MPC-TEST-003'
            )
        );

        System.assertEquals(
            false,
            returnedPartNumbers.contains(
                'MPC-TEST-004'
            ),
            'Inactive Part Catalog records must be excluded.'
        );
    }

    // =========================================================
    // MANUFACTURER TRIMMING
    // =========================================================

    @IsTest
    static void getCompatiblePartsTrimsManufacturerInput() {

        Test.startTest();

        List<ManagerPartCatalogController.PartOption> results =
            ManagerPartCatalogController.getCompatibleParts(
                '   Roland   ',
                'DWX-52D'
            );

        Test.stopTest();

        System.assertEquals(
            3,
            results.size(),
            'Leading and trailing manufacturer whitespace should be removed.'
        );
    }

    // =========================================================
    // UNKNOWN MANUFACTURER
    // =========================================================

    @IsTest
    static void getCompatiblePartsReturnsEmptyForUnknownManufacturer() {

        Test.startTest();

        List<ManagerPartCatalogController.PartOption> results =
            ManagerPartCatalogController.getCompatibleParts(
                'Manufacturer That Does Not Exist',
                'DWX-52D'
            );

        Test.stopTest();

        System.assertEquals(
            0,
            results.size(),
            'A manufacturer with no active catalog records should return an empty list.'
        );
    }

    // =========================================================
    // DTO FIELD MAPPING
    // =========================================================

    @IsTest
    static void getCompatiblePartsMapsPartOptionFieldsCorrectly() {

        Part_Catalog__c sourcePart = [
            SELECT
                Id,
                Name,
                Part_Number__c,
                Manufacturer__c,
                Compatible_Model__c,
                Parts_Category__c
            FROM Part_Catalog__c
            WHERE Part_Number__c = 'MPC-TEST-001'
            LIMIT 1
        ];

        Test.startTest();

        List<ManagerPartCatalogController.PartOption> results =
            ManagerPartCatalogController.getCompatibleParts(
                'Roland',
                'DWX-52D'
            );

        Test.stopTest();

        ManagerPartCatalogController.PartOption matchingOption;

        for (
            ManagerPartCatalogController.PartOption option :
            results
        ) {
            if (
                option.partNumber ==
                'MPC-TEST-001'
            ) {
                matchingOption = option;
                break;
            }
        }

        System.assertNotEquals(
            null,
            matchingOption,
            'The Alpha Spindle Bearing should be returned.'
        );

        System.assertEquals(
            sourcePart.Id,
            matchingOption.id
        );

        System.assertEquals(
            'Alpha Spindle Bearing',
            matchingOption.name
        );

        System.assertEquals(
            'MPC-TEST-001',
            matchingOption.partNumber
        );

        System.assertEquals(
            'Roland',
            matchingOption.manufacturer
        );

        System.assertEquals(
            'DWX-52D',
            matchingOption.compatibleModel
        );

        System.assertEquals(
            'Spindle',
            matchingOption.category
        );
    }

    // =========================================================
    // ORDER BY NAME
    // =========================================================

    @IsTest
    static void getCompatiblePartsReturnsPartsOrderedByName() {

        Test.startTest();

        List<ManagerPartCatalogController.PartOption> results =
            ManagerPartCatalogController.getCompatibleParts(
                'Roland',
                'DWX-52D'
            );

        Test.stopTest();

        System.assertEquals(
            3,
            results.size()
        );

        System.assertEquals(
            'Alpha Spindle Bearing',
            results[0].name
        );

        System.assertEquals(
            'Beta Coolant Filter',
            results[1].name
        );

        System.assertEquals(
            'Gamma Door Sensor',
            results[2].name
        );
    }

    // =========================================================
    // CURRENT MODEL PARAMETER BEHAVIOR
    // =========================================================

    @IsTest
    static void getCompatiblePartsCurrentlyDoesNotFilterByModel() {

        /*
         * The current production controller accepts a model
         * parameter but does not include it in the SOQL or
         * perform model filtering after the query.
         *
         * This test documents the CURRENT controller behavior.
         */

        Test.startTest();

        List<ManagerPartCatalogController.PartOption> dwx52Results =
            ManagerPartCatalogController.getCompatibleParts(
                'Roland',
                'DWX-52D'
            );

        List<ManagerPartCatalogController.PartOption> unrelatedModelResults =
            ManagerPartCatalogController.getCompatibleParts(
                'Roland',
                'MODEL-THAT-DOES-NOT-EXIST'
            );

        List<ManagerPartCatalogController.PartOption> nullModelResults =
            ManagerPartCatalogController.getCompatibleParts(
                'Roland',
                null
            );

        Test.stopTest();

        System.assertEquals(
            3,
            dwx52Results.size()
        );

        System.assertEquals(
            3,
            unrelatedModelResults.size(),
            'The current controller filters by manufacturer only.'
        );

        System.assertEquals(
            3,
            nullModelResults.size(),
            'The current controller does not require the model parameter.'
        );
    }
}