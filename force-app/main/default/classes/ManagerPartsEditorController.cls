public with sharing class ManagerPartsEditorController {
    public class PartOption {
        @AuraEnabled
        public Id id;

        @AuraEnabled
        public String name;

        @AuraEnabled
        public String partNumber;

        @AuraEnabled
        public String manufacturer;

        @AuraEnabled
        public String compatibleModel;

        @AuraEnabled
        public String category;

        @AuraEnabled
        public String keywords;

        @AuraEnabled
        public String stockStatus;
    }

    @AuraEnabled(cacheable=true)
    public static List<PartOption> getAvailableParts(String manufacturer) {
        List<PartOption> results = new List<PartOption>();

        if (String.isBlank(manufacturer)) {
            return results;
        }

        for (Part_Catalog__c catalogPart : [
                SELECT
                    Id,
                    Name,
                    Part_Number__c,
                    Manufacturer__c,
                    Compatible_Model__c,
                    Parts_Category__c,
                    Keyword_Aliases__c,
                    Stock_Status__c
                FROM Part_Catalog__c
                WHERE Active__c = true
                AND Manufacturer__c = :manufacturer
                ORDER BY Name
            ]
        ) {
            PartOption option = new PartOption();

            option.id = catalogPart.Id;
            option.name = catalogPart.Name;
            option.partNumber = catalogPart.Part_Number__c;
            option.manufacturer = catalogPart.Manufacturer__c;
            option.compatibleModel = catalogPart.Compatible_Model__c;
            option.category = catalogPart.Parts_Category__c;
            option.keywords = catalogPart.Keyword_Aliases__c;
            option.stockStatus = catalogPart.Stock_Status__c;

            results.add(option);
        }

        return results;
    }
}