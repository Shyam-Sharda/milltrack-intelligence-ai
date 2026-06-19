public with sharing class CreateWorkOrderParts {
    public class Request {
        @InvocableVariable(required=true)
        public Id workOrderId;

        @InvocableVariable(required=true)
        public Id machineId;

        @InvocableVariable(required=true)
        public String recommendedPartsJson;
    }

    public class Result {
        @InvocableVariable
        public Integer createdCount;

        @InvocableVariable
        public String unmatchedParts;

        @InvocableVariable
        public String statusMessage;
    }

    private class PartRequest {
        String name;
        Integer quantity;
    }

    @InvocableMethod(label='Create Work Order Parts')
    public static List<Result> createParts(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null || requests.isEmpty()) {
            Result res = new Result();
            res.createdCount = 0;
            res.unmatchedParts = '';
            res.statusMessage = 'No requests were provided.';
            results.add(res);
            return results;
        }

        for (Request req : requests) {
            Result res = new Result();
            res.createdCount = 0;
            res.unmatchedParts = '';

            List<String> unmatched = new List<String>();

            try {
                if (req == null) {
                    res.statusMessage = 'Request was blank.';
                    results.add(res);
                    continue;
                }

                if (req.workOrderId == null) {
                    res.statusMessage = 'Missing Work Order Id.';
                    results.add(res);
                    continue;
                }

                if (req.machineId == null) {
                    res.statusMessage = 'Missing Machine Id.';
                    results.add(res);
                    continue;
                }

                if (String.isBlank(req.recommendedPartsJson)) {
                    res.statusMessage = 'No recommended parts JSON provided.';
                    results.add(res);
                    continue;
                }

                List<PartRequest> requestedParts = parseParts(req.recommendedPartsJson);

                if (requestedParts.isEmpty()) {
                    res.statusMessage = 'No valid parts found in JSON.';
                    results.add(res);
                    continue;
                }

                List<Asset> machines = [
                    SELECT Id, Manufacturer__c, Model__c
                    FROM Asset
                    WHERE Id = :req.machineId
                    LIMIT 1
                ];

                if (machines.isEmpty()) {
                    res.statusMessage = 'Machine record was not found.';
                    results.add(res);
                    continue;
                }

                Asset machine = machines[0];

                List<Part_Catalog__c> catalogParts = [
                    SELECT Id, Name, Part_Number__c, Manufacturer__c, Compatible_Model__c,
                        Parts_Category__c, Supplier_Name__c, Supplier_Phone__c,
                        Order_URL__c, Active__c, Keyword_Aliases__c
                    FROM Part_Catalog__c
                    WHERE Active__c = true
                ];

                if (catalogParts.isEmpty()) {
                    res.statusMessage = 'No active Part Catalog records were found.';
                    results.add(res);
                    continue;
                }

                List<Work_Order_Part__c> existingParts = [
                    SELECT Id, Part_Catalog__c, Quantity__c, Quantity_Needed__c
                    FROM Work_Order_Part__c
                    WHERE Work_Order__c = :req.workOrderId
                    AND Part_Catalog__c != null
                ];

                Map<Id, Work_Order_Part__c> existingPartByCatalogId = new Map<Id, Work_Order_Part__c>();

                for (Work_Order_Part__c existingPart : existingParts) {
                    existingPartByCatalogId.put(existingPart.Part_Catalog__c, existingPart);
                }

                List<Work_Order_Part__c> partsToCreate = new List<Work_Order_Part__c>();
                List<Work_Order_Part__c> partsToUpdate = new List<Work_Order_Part__c>();

                Set<Id> updatedExistingPartIds = new Set<Id>();

                for (PartRequest requested : requestedParts) {
                    if (requested == null || String.isBlank(requested.name)) {
                        continue;
                    }

                    Part_Catalog__c match = findBestMatch(requested.name, machine, catalogParts);

                    if (match == null) {
                        unmatched.add(requested.name);
                        continue;
                    }

                    Integer qty = requested.quantity == null || requested.quantity < 1 ? 1 : requested.quantity;

                    if (existingPartByCatalogId.containsKey(match.Id)) {
                        Work_Order_Part__c existingPart = existingPartByCatalogId.get(match.Id);

                        Decimal currentQty = existingPart.Quantity_Needed__c == null ? 0 : existingPart.Quantity_Needed__c;

                        existingPart.Quantity_Needed__c = currentQty + qty;

                        if (existingPart.Quantity__c == null) {
                            existingPart.Quantity__c = qty;
                        } else {
                            existingPart.Quantity__c = existingPart.Quantity__c + qty;
                        }

                        if (!updatedExistingPartIds.contains(existingPart.Id)) {
                            partsToUpdate.add(existingPart);
                            updatedExistingPartIds.add(existingPart.Id);
                        }

                        continue;
                    }

                    Work_Order_Part__c wop = new Work_Order_Part__c();
                    wop.Work_Order__c = req.workOrderId;
                    wop.Machine__c = req.machineId;
                    wop.Part_Catalog__c = match.Id;
                    wop.Quantity__c = qty;
                    wop.Quantity_Needed__c = qty;
                    wop.Supplier_Name__c = match.Supplier_Name__c;
                    wop.Supplier_Phone__c = match.Supplier_Phone__c;
                    wop.Order_URL__c = match.Order_URL__c;
                    wop.Order_Status__c = getDefaultOrderStatus();
                    wop.Notes__c = 'Created from AI recommended parts.';

                    partsToCreate.add(wop);
                    existingPartByCatalogId.put(match.Id, wop);
                }

                Integer successCreateCount = 0;
                Integer successUpdateCount = 0;
                List<String> saveErrors = new List<String>();

                if (!partsToCreate.isEmpty()) {
                    Database.SaveResult[] insertResults = Database.insert(partsToCreate, false);

                    for (Database.SaveResult sr : insertResults) {
                        if (sr.isSuccess()) {
                            successCreateCount++;
                        } else {
                            for (Database.Error err : sr.getErrors()) {
                                saveErrors.add(err.getMessage());
                            }
                        }
                    }
                }

                if (!partsToUpdate.isEmpty()) {
                    Database.SaveResult[] updateResults = Database.update(partsToUpdate, false);

                    for (Database.SaveResult sr : updateResults) {
                        if (sr.isSuccess()) {
                            successUpdateCount++;
                        } else {
                            for (Database.Error err : sr.getErrors()) {
                                saveErrors.add(err.getMessage());
                            }
                        }
                    }
                }

                res.createdCount = successCreateCount;
                res.unmatchedParts = String.join(unmatched, ', ');

                if (!saveErrors.isEmpty()) {
                    res.statusMessage = 'Created ' + successCreateCount + ' Work Order Part record(s). Updated ' + 
                    successUpdateCount + ' existing record(s). Some records failed: ' + String.join(saveErrors, ' | ');
                } else if (successCreateCount > 0 || successUpdateCount > 0) {
                    res.statusMessage = 'Created ' + successCreateCount + ' Work Order Part record(s). Updated ' + 
                    successUpdateCount + ' existing record(s).';
                } else {
                    res.statusMessage = 'No Work Order Part records were created or updated.';
                }

            } catch (Exception e) {
                res.createdCount = 0;
                res.unmatchedParts = String.join(unmatched, ', ');
                res.statusMessage = 'Error creating Work Order Parts: ' + e.getMessage();
            }

            results.add(res);
        }

        return results;
    }

    private static List<PartRequest> parseParts(String jsonText) {
        List<PartRequest> output = new List<PartRequest>();

        try {
            Object raw = JSON.deserializeUntyped(jsonText);

            if (!(raw instanceof Map<String, Object>)) {
                return output;
            }

            Map<String, Object> root = (Map<String, Object>) raw;

            if (!root.containsKey('parts')) {
                return output;
            }

            Object partsObj = root.get('parts');

            if (!(partsObj instanceof List<Object>)) {
                return output;
            }

            for (Object item : (List<Object>) partsObj) {
                if (!(item instanceof Map<String, Object>)) {
                    continue;
                }

                Map<String, Object> partMap = (Map<String, Object>) item;

                PartRequest pr = new PartRequest();

                if (!partMap.containsKey('name') || partMap.get('name') == null) {
                    continue;
                }

                pr.name = String.valueOf(partMap.get('name')).trim();

                if (String.isBlank(pr.name) || pr.name.toLowerCase() == 'null') {
                    continue;
                }

                pr.quantity = safeInteger(partMap.get('quantity'));

                if (pr.quantity == null || pr.quantity < 1) {
                    pr.quantity = 1;
                }

                output.add(pr);
            }
        } catch (Exception e) {
            return output;
        }

        return output;
    }

    private static Integer safeInteger(Object value) {
        if (value == null) {
            return 1;
        }

        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return 1;
        }
    }

    private static Part_Catalog__c findBestMatch(String requestedName, Asset machine, List<Part_Catalog__c> catalogParts) {
        if (String.isBlank(requestedName) || catalogParts == null || catalogParts.isEmpty()) {
            return null;
        }

        String search = normalize(requestedName);

        Part_Catalog__c bestMatch;
        Integer bestScore = 0;

        for (Part_Catalog__c part : catalogParts) {
            Integer score = 0;
            Integer nameScore = 0;

            String partName = normalize(part.Name);
            String aliases = normalize(part.Keyword_Aliases__c);
            String category = normalize(part.Parts_Category__c);
            String manufacturer = normalize(part.Manufacturer__c);
            String compatibleModel = normalize(part.Compatible_Model__c);

            if (partName == search) {
                nameScore += 100;
            }

            if (!String.isBlank(partName) &&
                !String.isBlank(search) &&
                (partName.contains(search) || search.contains(partName))) {
                nameScore += 70;
            }

            if (!String.isBlank(aliases) &&
                !String.isBlank(search) &&
                aliases.contains(search)) {
                nameScore += 60;
            }

            if (!String.isBlank(category) &&
                !String.isBlank(search) &&
                search.length() >= 4 &&
                category.contains(search)) {
                nameScore += 30;
            }

            score += nameScore;

            if (nameScore > 0 &&
                machine != null &&
                !String.isBlank(machine.Manufacturer__c) &&
                manufacturer.contains(normalize(machine.Manufacturer__c))) {
                score += 25;
            }

            if (nameScore > 0 &&
                machine != null &&
                !String.isBlank(machine.Model__c) &&
                compatibleModel.contains(normalize(machine.Model__c))) {
                score += 25;
            }

            if (score > bestScore) {
                bestScore = score;
                bestMatch = part;
            }
        }

        return bestScore >= 50 ? bestMatch : null;
    }

    private static String normalize(String value) {
        if (String.isBlank(value)) {
            return '';
        }

        return value.toLowerCase()
            .replace('-', ' ')
            .replace('_', ' ')
            .replace('/', ' ')
            .trim();
    }

    private static String getDefaultOrderStatus() {
        try {
            Schema.DescribeFieldResult fieldDescribe = Work_Order_Part__c.Order_Status__c.getDescribe();

            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (entry.isDefaultValue() && entry.isActive()) {
                    return entry.getValue();
                }
            }

            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (entry.isActive()) {
                    return entry.getValue();
                }
            }
        } catch (Exception e) {
            return null;
        }

        return null;
    }
}
