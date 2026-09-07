public with sharing class ManagerPartCatalogController {

    @AuraEnabled(cacheable=true)
    public static List<PartOption> getCompatibleParts(
        String manufacturer,
        String model
    ) {

        if (String.isBlank(manufacturer)) {
            return new List<PartOption>();
        }

        Map<String, Object> binds =
            new Map<String, Object>{
                'manufacturer' =>
                    manufacturer.trim()
            };

        List<Part_Catalog__c> catalogParts =
            Database.queryWithBinds(
                'SELECT ' +
                    'Id, ' +
                    'Name, ' +
                    'Part_Number__c, ' +
                    'Manufacturer__c, ' +
                    'Compatible_Model__c, ' +
                    'Parts_Category__c ' +
                'FROM Part_Catalog__c ' +
                'WHERE ' +
                    'Active__c = true ' +
                    'AND Manufacturer__c = :manufacturer ' +
                'ORDER BY Name ' +
                'LIMIT 200',
                binds,
                AccessLevel.USER_MODE
            );

        List<PartOption> results =
            new List<PartOption>();

        for (
            Part_Catalog__c part :
            catalogParts
        ) {

            PartOption option =
                new PartOption();

            option.id =
                part.Id;

            option.name =
                part.Name;

            option.partNumber =
                part.Part_Number__c;

            option.manufacturer =
                part.Manufacturer__c;

            option.compatibleModel =
                part.Compatible_Model__c;

            option.category =
                part.Parts_Category__c;

            results.add(
                option
            );
        }

        return results;
    }

    public class PartOption {

        @AuraEnabled
        public Id id { get; set; }

        @AuraEnabled
        public String name { get; set; }

        @AuraEnabled
        public String partNumber { get; set; }

        @AuraEnabled
        public String manufacturer { get; set; }

        @AuraEnabled
        public String compatibleModel { get; set; }

        @AuraEnabled
        public String category { get; set; }
    }
}