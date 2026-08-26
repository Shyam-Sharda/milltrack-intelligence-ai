public without sharing class GetRelevantHistoricalRepairsForCase {
    private static final Integer DEFAULT_MAX_RESULTS = 3;
    private static final Integer MAX_RESULTS_ALLOWED = 5;
    private static final Integer CANDIDATE_LIMIT = 30;

    /*
     * Common words that should not make two repair records appear related.
     *
     * Manager Historical Repair Intelligence V1 intentionally uses
     * lightweight, deterministic lexical matching rather than
     * semantic/vector search.
     */
    private static final Set<String> STOP_WORDS = new Set<String>{
        'the', 'and', 'for', 'with', 'this', 'that', 'from', 'into',
        'onto', 'when', 'then', 'than', 'have', 'has', 'had', 'was',
        'were', 'are', 'is', 'been', 'being', 'can', 'could', 'should',
        'would', 'will', 'may', 'might', 'not', 'but', 'about', 'after',
        'before', 'during', 'while',

        // General equipment/service words.
        'machine', 'mill', 'milling', 'issue', 'problem', 'repair',
        'service', 'customer', 'technician', 'work', 'order',
        'model', 'unit', 'equipment',

        // Generic repair verbs that do not establish problem similarity.
        'replace', 'replaced', 'replacing', 'replacement',
        'repairing', 'repaired',
        'fix', 'fixed', 'fixing',
        'install', 'installed', 'installing',
        'remove', 'removed',
        'performed', 'completed',

        // Common filler / contraction tokens.
        'isnt', 'doesnt', 'didnt', 'wont', 'cant'
    };


    public class Request {

        @InvocableVariable(
            required=true
            label='Current Case ID'
            description='Salesforce Case ID for the service request that is being converted into a proposed Work Order.'
        )
        public Id caseId;


        @InvocableVariable(
            label='Maximum Results'
            description='Maximum number of relevant successful historical repair precedents to return. Defaults to 3 and cannot exceed 5.'
        )
        public Integer maxResults;
    }


    public class Result {

        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public String statusCode;

        @InvocableVariable
        public String statusMessage;

        @InvocableVariable
        public Integer matchCount;

        @InvocableVariable
        public String historicalRepairContext;
    }


    private class ScoredRepair implements Comparable {

        public Maintenance_Log__c maintenanceLog;
        public Integer score;
        public Integer overlapCount;
        public Boolean exactErrorMatch;
        public Boolean sameAsset;
        public Boolean sameModel;
        public Boolean sameManufacturer;
        public Set<String> matchedTerms;

        public ScoredRepair() {
            score = 0;
            overlapCount = 0;
            exactErrorMatch = false;
            sameAsset = false;
            sameModel = false;
            sameManufacturer = false;
            matchedTerms = new Set<String>();
        }

        public Integer compareTo(Object otherObject) {

            ScoredRepair other = (ScoredRepair) otherObject;

            if (score != other.score) {
                return score > other.score ? -1 : 1;
            }

            Date thisDate = maintenanceLog.Maintenance_Date__c;
            Date otherDate = other.maintenanceLog.Maintenance_Date__c;

            if (thisDate == otherDate) {
                return 0;
            }

            if (thisDate == null) {
                return 1;
            }

            if (otherDate == null) {
                return -1;
            }

            return thisDate > otherDate ? -1 : 1;
        }
    }


    @InvocableMethod(
        label='Get Relevant Historical Repairs for Case'
        description='Finds and ranks successful previous repairs that may be relevant to a current Case before the proposed Work Order is created. Historical repairs are supporting evidence only and do not establish the current diagnosis.'
    )
    public static List<Result> getRelevantHistoricalRepairsForCase(List<Request> requests) {

        List<Result> results = new List<Result>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        /*
         * Flow normally invokes this action for one Case at a time.
         * Each request is nevertheless processed independently.
         */
        for (Request request : requests) {
            results.add(processRequest(request));
        }

        return results;
    }


    private static Result processRequest(Request request) {
        Result result = new Result();

        result.success = false;
        result.matchCount = 0;
        result.historicalRepairContext = '';

        if (request == null || request.caseId == null) {
            result.statusCode = 'INVALID_REQUEST';
            result.statusMessage = 'A current Case ID is required.';
            return result;
        }

        try {
            /*
             * Retrieve the current Case.
             *
             * This is CURRENT service context and must never itself
             * be treated as historical repair evidence.
             */
            List<Case> currentCases = [
                SELECT
                    Id,
                    CaseNumber,
                    Subject,
                    Description,
                    Priority,
                    Error_Code__c,
                    AssetId
                FROM Case
                WHERE Id = :request.caseId
                WITH USER_MODE
                LIMIT 1
            ];

            if (currentCases.isEmpty()) {
                result.statusCode = 'CASE_NOT_FOUND';
                result.statusMessage = 'The current Case could not be retrieved.';
                return result;
            }

            Case currentCase = currentCases[0];

            /*
             * A machine/Asset is required in order to safely compare
             * service history.
             */
            if (currentCase.AssetId == null) {
                result.statusCode = 'NO_ASSET_CONTEXT';
                result.statusMessage = 'Historical Repair Intelligence requires an Asset on the current Case.';
                return result;
            }


            List<Asset> currentAssets = [
                SELECT
                    Id,
                    Manufacturer__c,
                    Model__c,
                    Serial_Number__c,
                    Machine_Status__c
                FROM Asset
                WHERE Id = :currentCase.AssetId
                WITH USER_MODE
                LIMIT 1
            ];

            if (currentAssets.isEmpty()) {
                result.statusCode = 'ASSET_NOT_FOUND';
                result.statusMessage = 'The Asset attached to the current Case could not be retrieved.';
                return result;
            }

            Asset currentAsset = currentAssets[0];

            String currentErrorCode = currentCase.Error_Code__c;

            /*
             * Current problem context comes only from the Case.
             *
             * Unlike Technician Historical Repair Intelligence, there is
             * no current Work Order yet.
             */
            String currentProblemContext = joinText(
                new List<String>{
                    currentCase.Subject,
                    currentCase.Description,
                    currentErrorCode
                }
            );

            Set<String> currentTerms = tokenize(currentProblemContext);

            /*
             * Manufacturer and model are scored separately and therefore
             * should not artificially inflate textual problem similarity.
             */
            Set<String> equipmentIdentityTerms = new Set<String>();

            equipmentIdentityTerms.addAll(tokenize(currentAsset.Manufacturer__c));

            equipmentIdentityTerms.addAll(tokenize(currentAsset.Model__c));

            currentTerms.removeAll(equipmentIdentityTerms);

            if (currentTerms.isEmpty() && String.isBlank(currentErrorCode)) {
                result.statusCode = 'MISSING_PROBLEM_CONTEXT';
                result.statusMessage = 'The current Case does not contain enough problem or symptom information to compare with historical repairs.';
                return result;
            }


            /*
             * V1 candidate retrieval:
             *
             * Only confirmed successful prior repair records qualify:
             *
             * - Issue Resolved = true
             * - Follow Up Required = false
             * - Repair or Emergency Service
             * - Asset is present
             *
             * Temporary repairs and unresolved visits are deliberately
             * excluded from successful precedent logic.
             *
             * Manufacturer/model establishes the machine family.
             * Exact model, same Asset, error code, symptom overlap,
             * repair type, and recency are used for ranking.
             */
            List<Maintenance_Log__c> candidates;

            if (!String.isBlank(currentAsset.Manufacturer__c)) {

                candidates = [
                    SELECT
                        Id,
                        Name,
                        Asset__c,
                        Asset__r.Manufacturer__c,
                        Asset__r.Model__c,
                        Asset__r.Serial_Number__c,
                        Work_Order__c,
                        Work_Order__r.WorkOrderNumber,
                        Work_Order__r.Subject,
                        Work_Order__r.CaseId,
                        Maintenance_Date__c,
                        Maintenance_Type__c,
                        Summary__c,
                        Root_Cause__c,
                        Parts_Used__c,
                        Technician_Notes__c,
                        Labor_Hours__c,
                        Issue_Resolved__c,
                        Follow_Up_Required__c
                    FROM Maintenance_Log__c
                    WHERE
                        Issue_Resolved__c = TRUE
                        AND Follow_Up_Required__c = FALSE
                        AND Maintenance_Type__c IN ('Repair', 'Emergency Service')
                        AND Asset__c != NULL
                        AND Asset__r.Manufacturer__c = :currentAsset.Manufacturer__c
                    WITH SYSTEM_MODE
                    ORDER BY
                        Maintenance_Date__c DESC NULLS LAST,
                        CreatedDate DESC
                    LIMIT :CANDIDATE_LIMIT
                ];

            } else if (!String.isBlank(currentAsset.Model__c)) {

                candidates = [
                    SELECT
                        Id,
                        Name,
                        Asset__c,
                        Asset__r.Manufacturer__c,
                        Asset__r.Model__c,
                        Asset__r.Serial_Number__c,
                        Work_Order__c,
                        Work_Order__r.WorkOrderNumber,
                        Work_Order__r.Subject,
                        Work_Order__r.CaseId,
                        Maintenance_Date__c,
                        Maintenance_Type__c,
                        Summary__c,
                        Root_Cause__c,
                        Parts_Used__c,
                        Technician_Notes__c,
                        Labor_Hours__c,
                        Issue_Resolved__c,
                        Follow_Up_Required__c
                    FROM Maintenance_Log__c
                    WHERE
                        Issue_Resolved__c = TRUE
                        AND Follow_Up_Required__c = FALSE
                        AND Maintenance_Type__c IN ('Repair', 'Emergency Service')
                        AND Asset__c != NULL
                        AND Asset__r.Model__c = :currentAsset.Model__c
                    WITH SYSTEM_MODE
                    ORDER BY
                        Maintenance_Date__c DESC NULLS LAST,
                        CreatedDate DESC
                    LIMIT :CANDIDATE_LIMIT
                ];

            } else {
                result.statusCode = 'NO_MACHINE_CONTEXT';
                result.statusMessage = 'The current Asset does not contain a manufacturer or model for historical comparison.';
                return result;
            }

            if (candidates.isEmpty()) {
                result.statusCode = 'NO_SUCCESSFUL_HISTORY';
                result.statusMessage = 'No prior successful repair records were found for comparison.';
                return result;
            }


            /*
             * Retrieve the Cases associated with historical Work Orders.
             *
             * This gives the ranking logic access to prior Case symptoms
             * and exact historical error codes without relying on a deep
             * relationship query.
             */
            Set<Id> historicalCaseIds = new Set<Id>();

            for (Maintenance_Log__c candidate : candidates) {

                if (candidate.Work_Order__r != null && candidate.Work_Order__r.CaseId != null && candidate.Work_Order__r.CaseId != currentCase.Id) {
                    historicalCaseIds.add(candidate.Work_Order__r.CaseId);
                }
            }


            Map<Id, Case> historicalCasesById = new Map<Id, Case>();

            if (!historicalCaseIds.isEmpty()) {

                historicalCasesById = new Map<Id, Case>([
                    SELECT
                        Id,
                        CaseNumber,
                        Subject,
                        Description,
                        Error_Code__c
                    FROM Case
                    WHERE Id IN :historicalCaseIds
                    WITH SYSTEM_MODE
                ]);
            }

            List<ScoredRepair> scoredRepairs = new List<ScoredRepair>();


            for (Maintenance_Log__c candidate : candidates) {

                /*
                 * Never allow service generated from the current Case
                 * to become historical evidence for that same Case.
                 *
                 * This also protects future reruns of the Flow after
                 * a Work Order may already exist.
                 */
                if (candidate.Work_Order__r != null && candidate.Work_Order__r.CaseId == currentCase.Id) {
                    continue;
                }

                Case historicalCase;

                if (candidate.Work_Order__r != null && candidate.Work_Order__r.CaseId != null) {
                    historicalCase = historicalCasesById.get(candidate.Work_Order__r.CaseId);
                }

                String candidateErrorCode = historicalCase == null ? null : historicalCase.Error_Code__c;

                /*
                 * Historical similarity can come from the actual completed
                 * Maintenance Log, its Work Order, or its related historical
                 * Case.
                 */
                String historicalContext = joinText(
                    new List<String>{
                        candidate.Summary__c,
                        candidate.Root_Cause__c,
                        candidate.Parts_Used__c,
                        candidate.Technician_Notes__c,
                        candidate.Work_Order__r == null ? null : candidate.Work_Order__r.Subject,
                        historicalCase == null ? null : historicalCase.Subject,
                        historicalCase == null ? null : historicalCase.Description,
                        candidateErrorCode
                    }
                );


                Set<String> historicalTerms = tokenize(historicalContext);

                historicalTerms.removeAll(equipmentIdentityTerms);

                ScoredRepair scored = new ScoredRepair();

                scored.maintenanceLog = candidate;

                scored.sameAsset = candidate.Asset__c == currentAsset.Id;

                scored.sameManufacturer =
                    equalsIgnoreCase(candidate.Asset__r == null ? null : candidate.Asset__r.Manufacturer__c, currentAsset.Manufacturer__c);

                scored.sameModel = equalsIgnoreCase(candidate.Asset__r == null ? null : candidate.Asset__r.Model__c, currentAsset.Model__c);

                scored.exactErrorMatch =
                    !String.isBlank(currentErrorCode) &&
                    !String.isBlank(candidateErrorCode) &&
                    normalize(currentErrorCode) == normalize(candidateErrorCode);

                for (String term : currentTerms) {

                    if (historicalTerms.contains(term)) {
                        scored.matchedTerms.add(term);
                    }
                }

                scored.overlapCount = scored.matchedTerms.size();

                /*
                 * Equipment relevance.
                 *
                 * A repair on the same Asset naturally receives the
                 * same-Asset, same-model, and same-manufacturer bonuses
                 * when those identities match.
                 */
                if (scored.sameAsset) {
                    scored.score += 10;
                }

                if (scored.sameModel) {
                    scored.score += 20;
                }

                if (scored.sameManufacturer) {
                    scored.score += 8;
                }

                /*
                 * Problem relevance.
                 */
                if (scored.exactErrorMatch) {
                    scored.score += 40;
                }

                scored.score += Math.min(scored.overlapCount * 8, 48);

                /*
                 * Successful repair quality.
                 *
                 * All candidates are already resolved and require
                 * no follow-up.
                 */
                if (candidate.Maintenance_Type__c == 'Repair') {
                    scored.score += 8;

                } else if (candidate.Maintenance_Type__c == 'Emergency Service') {
                    scored.score += 5;
                }

                /*
                 * Small recency bonus.
                 *
                 * Recency must never outweigh actual problem similarity.
                 */
                if (candidate.Maintenance_Date__c != null) {

                    Integer ageDays = candidate.Maintenance_Date__c.daysBetween(Date.today());

                    if (ageDays >= 0 && ageDays <= 180) {
                        scored.score += 4;

                    } else if (ageDays > 180 && ageDays <= 365) {
                        scored.score += 2;
                    }
                }

                /*
                 * A machine identity match by itself is not enough.
                 *
                 * A candidate becomes eligible only when there is:
                 *
                 * - an exact matching error code, OR
                 * - at least two meaningful overlapping problem terms.
                 */
                Boolean hasMeaningfulProblemMatch = scored.exactErrorMatch || scored.overlapCount >= 2;

                if (hasMeaningfulProblemMatch) {
                    scoredRepairs.add(scored);
                }
            }

            if (scoredRepairs.isEmpty()) {
                result.statusCode = 'NO_RELEVANT_HISTORY';

                result.statusMessage =
                    'Successful historical repairs exist, but none were relevant enough to the current Case to present as repair precedents.';

                return result;
            }

            scoredRepairs.sort();

            Integer requestedMax = request.maxResults == null ? DEFAULT_MAX_RESULTS : request.maxResults;

            if (requestedMax < 1) {
                requestedMax = DEFAULT_MAX_RESULTS;
            }

            requestedMax = Math.min(requestedMax, MAX_RESULTS_ALLOWED);

            Integer resultCount = Math.min(requestedMax, scoredRepairs.size());

            String context = buildHistoricalRepairContext(currentCase, currentAsset, currentErrorCode, scoredRepairs, resultCount);

            result.success = true;
            result.statusCode = 'SUCCESS';
            result.matchCount = resultCount;
            result.statusMessage = 'Relevant successful historical repairs were found.';
            result.historicalRepairContext = context;

            return result;


        } catch (Exception e) {
            result.success = false;
            result.statusCode = 'SYSTEM_ERROR';
            result.statusMessage = 'Historical Repair Intelligence could not retrieve repair history.';
            result.matchCount = 0;
            result.historicalRepairContext = '';

            return result;
        }
    }


    private static String buildHistoricalRepairContext(
        Case currentCase,
        Asset currentAsset,
        String currentErrorCode,
        List<ScoredRepair> scoredRepairs,
        Integer resultCount
    ) {

        List<String> lines = new List<String>();

        lines.add('HISTORICAL REPAIR INTELLIGENCE');

        lines.add('');

        if (!String.isBlank(currentCase.CaseNumber)) {
            lines.add('Current Case: ' + currentCase.CaseNumber);
        }

        lines.add('Current machine: ' + safe(currentAsset.Manufacturer__c) + ' ' + safe(currentAsset.Model__c));

        if (!String.isBlank(currentAsset.Serial_Number__c)) {
            lines.add('Current serial number: ' + currentAsset.Serial_Number__c);
        }

        if (!String.isBlank(currentErrorCode)) {
            lines.add('Current error code: ' + currentErrorCode);
        }

        lines.add('');

        lines.add('Relevant successful repair precedents:');

        for (Integer i = 0; i < resultCount; i++) {

            ScoredRepair scored = scoredRepairs[i];

            Maintenance_Log__c logRecord = scored.maintenanceLog;

            lines.add('');

            lines.add(String.valueOf(i + 1) + '. ' + logRecord.Name);

            if (logRecord.Maintenance_Date__c != null) {
                lines.add('Date: ' +  String.valueOf(logRecord.Maintenance_Date__c));
            }

            if (logRecord.Asset__r != null) {

                lines.add('Machine: ' + safe(logRecord.Asset__r.Manufacturer__c) + ' ' + safe(logRecord.Asset__r.Model__c));

                if (!String.isBlank( logRecord.Asset__r.Serial_Number__c)) {
                    lines.add('Historical serial number: ' + logRecord.Asset__r.Serial_Number__c);
                }
            }

            if (logRecord.Work_Order__r != null && !String.isBlank(logRecord.Work_Order__r.WorkOrderNumber)) {
                lines.add('Historical Work Order: ' + logRecord.Work_Order__r.WorkOrderNumber);
            }

            /*
             * This explicit same-Asset indicator is intentionally exposed
             * so Prompt Builder can distinguish:
             *
             * - a true previous failure of this exact Asset
             * - a relevant precedent from another machine
             */
            lines.add('Same current Asset: ' + (scored.sameAsset ? 'Yes' : 'No'));

            List<String> basis = new List<String>();

            if (scored.exactErrorMatch) {
                basis.add('same error code');
            }

            if (scored.sameAsset) {
                basis.add('same Asset');
            }

            if (scored.sameModel) {
                basis.add('same model');
            } else if (scored.sameManufacturer) {
                basis.add('same manufacturer');
            }

            if (!scored.matchedTerms.isEmpty()) {

                List<String> matchedTerms = new List<String>(scored.matchedTerms);

                matchedTerms.sort();

                Integer termsToShow = Math.min(5,  matchedTerms.size());

                List<String> displayedTerms = new List<String>();

                for (Integer j = 0; j < termsToShow; j++) {
                    displayedTerms.add(matchedTerms[j]);
                }

                basis.add('matching problem terms: ' + String.join(displayedTerms, ', '));
            }

            if (!basis.isEmpty()) {
                lines.add('Why relevant: ' + String.join(basis, '; '));
            }

            if (!String.isBlank(logRecord.Summary__c)) {
                lines.add('Successful repair: ' +  clip(logRecord.Summary__c, 600));
            }

            if (!String.isBlank(logRecord.Root_Cause__c)) {
                lines.add('Recorded root cause: ' + clip(logRecord.Root_Cause__c, 500));
            }

            if (!String.isBlank(logRecord.Parts_Used__c)) {
                lines.add('Parts used: ' + clip(logRecord.Parts_Used__c, 400));
            }

            if (!String.isBlank(logRecord.Technician_Notes__c)) {
                lines.add('Technician notes: ' + clip(logRecord.Technician_Notes__c, 800));
            }

            if (logRecord.Labor_Hours__c != null) {
                lines.add('Labor hours: ' + String.valueOf(logRecord.Labor_Hours__c));
            }

            lines.add('Outcome: Issue resolved; no follow-up required.');
        }

        lines.add('');

        lines.add(
            'IMPORTANT: These historical repair precedents are supporting evidence only. ' +
            'They do not prove that the current machine has the same root cause. ' +
            'A repair from another Asset is a relevant precedent, not a previous failure of the current Asset. ' +
            'Historical parts used do not confirm that the same parts are required now. ' +
            'Verify the current machine condition and use approved MillTrack service documentation before finalizing the repair plan or ordering parts.'
        );

        return String.join(lines, '\n');
    }


    private static Set<String> tokenize(String value) {
        Set<String> terms = new Set<String>();

        String normalizedValue =  normalize(value);

        if (String.isBlank(normalizedValue)) {
            return terms;
        }

        for (String term : normalizedValue.split('\\s+')) {
            if (String.isBlank(term) || term.length() < 3 || STOP_WORDS.contains(term)) {
                continue;
            }

            terms.add(term);
        }

        return terms;
    }


    private static String normalize(String value) {
        if (String.isBlank(value)) {
            return '';
        }


        return value.toLowerCase().replaceAll('[^a-z0-9]+', ' ').trim();
    }


    private static Boolean equalsIgnoreCase(String leftValue, String rightValue) {
        if (String.isBlank(leftValue) || String.isBlank(rightValue)) {
            return false;
        }


        return leftValue.trim().toLowerCase() == rightValue.trim().toLowerCase();
    }


    private static String joinText(List<String> values) {
        List<String> populated = new List<String>();

        for (String value : values) {

            if (!String.isBlank(value)) {
                populated.add(value);
            }
        }


        return String.join(populated, ' ');
    }


    private static String clip(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return '';
        }

        String trimmed = value.trim();

        if (trimmed.length() <= maxLength) {
            return trimmed;
        }

        return trimmed.substring(0, maxLength) + '…';
    }

    private static String safe(String value) {
        return String.isBlank(value) ? 'Not available' : value.trim();
    }
}