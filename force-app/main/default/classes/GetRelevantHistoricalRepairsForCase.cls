public without sharing class GetRelevantHistoricalRepairsForCase {
    private static final Integer DEFAULT_MAX_RESULTS = 3;
    private static final Integer MAX_RESULTS_ALLOWED = 5;
    private static final Integer CANDIDATE_LIMIT = 30;
    /*
     * Common words that should not make two repair records appear related.
     *
     * Manager Historical Repair Intelligence V2 intentionally uses
     * lightweight, deterministic lexical matching rather than
     * semantic/vector search.
     */
    private static final Set<String> STOP_WORDS = new Set<String>{
        // General language / filler.
        'the', 'and', 'for', 'with', 'this', 'that', 'from', 'into',
        'onto', 'when', 'then', 'than', 'have', 'has', 'had', 'was',
        'were', 'are', 'is', 'been', 'being', 'can', 'could', 'should',
        'would', 'will', 'may', 'might', 'not', 'but', 'about', 'after',
        'before', 'during', 'while', 'its', 'their', 'there', 'these',
        'those', 'they', 'them', 'our', 'your',
        // General equipment/service words.
        'machine', 'mill', 'milling', 'issue', 'problem', 'repair',
        'service', 'customer', 'technician', 'work', 'order',
        'model', 'unit', 'equipment',
        // Generic reporting language.
        'report', 'reports', 'reported', 'reporting',
        'observe', 'observed', 'observes',
        'notice', 'noticed',
        'show', 'shows', 'showing',
        'state', 'states', 'stated',
        // Generic condition/failure language.
        // These words do not identify WHAT failed.
        'fail', 'fails', 'failed', 'failing', 'failure', 'failures',
        'normal', 'normally',
        'works', 'worked', 'working',
        'function', 'functions', 'functional', 'functioning',
        'operation', 'operating',
        'condition',
        'result', 'results',
        'outcome',
        // Generic movement/process words.
        'go', 'goes', 'going', 'went',
        'step', 'steps',
        'process', 'processes',
        'attempt', 'attempts', 'attempted',
        'multiple',
        'again',
        'still',
        'continue', 'continues', 'continued',
        'persist', 'persists', 'persisted', 'persistent',
        // Generic error language. Actual Error_Code__c values are
        // evaluated separately as exact matches.
        'error', 'errors',
        'message', 'messages',
        'warning', 'warnings',
        // Generic repair verbs that do not establish problem similarity.
        'replace', 'replaced', 'replacing', 'replacement',
        'repairing', 'repaired',
        'fix', 'fixed', 'fixing',
        'install', 'installed', 'installing',
        'remove', 'removed',
        'performed', 'completed',
        'clean', 'cleaned', 'cleaning',
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
        @AuraEnabled
        public List<HistoricalPrecedentUi> precedents { get; set; }
    }
    public class HistoricalPrecedentUi {
        @AuraEnabled public Id maintenanceLogId { get; set; }
        @AuraEnabled public String maintenanceLogName { get; set; }
        @AuraEnabled public Date maintenanceDate { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public Boolean sameAsset { get; set; }
        @AuraEnabled public Boolean sameModel { get; set; }
        @AuraEnabled public String whyRelevant { get; set; }
        @AuraEnabled public String problemSummary { get; set; }
        @AuraEnabled public String successfulRepair { get; set; }
        @AuraEnabled public String rootCause { get; set; }
        @AuraEnabled public String partsUsed { get; set; }
        @AuraEnabled public String technicianNotes { get; set; }
        @AuraEnabled public Decimal laborHours { get; set; }
        @AuraEnabled public String outcome { get; set; }
    }
    private class ScoredRepair implements Comparable {
        public Maintenance_Log__c maintenanceLog;
        public String problemSummary;
        public Integer score;
        public Integer overlapCount;
        public Integer subjectOverlapCount;
        public Boolean exactErrorMatch;
        public Boolean sameAsset;
        public Boolean sameModel;
        public Boolean sameManufacturer;
        public Set<String> matchedTerms;
        public Set<String> matchedSubjectTerms;
        public ScoredRepair() {
            score = 0;
            overlapCount = 0;
            subjectOverlapCount = 0;
            exactErrorMatch = false;
            sameAsset = false;
            sameModel = false;
            sameManufacturer = false;
            matchedTerms = new Set<String>();
            matchedSubjectTerms = new Set<String>();
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
    @AuraEnabled(cacheable=true)
    public static Result getHistoricalRepairsForLwc(Id caseId, Integer maxResults) {
        if (caseId == null) {
            Result invalidResult = new Result();
            invalidResult.success = false;
            invalidResult.statusCode = 'INVALID_REQUEST';
            invalidResult.statusMessage = 'A current Case ID is required.';
            invalidResult.matchCount = 0;
            invalidResult.historicalRepairContext = '';
            invalidResult.precedents = new List<HistoricalPrecedentUi>();
            return invalidResult;
        }
        Request request = new Request();
        request.caseId = caseId;
        request.maxResults = maxResults == null ? DEFAULT_MAX_RESULTS : maxResults;
        return processRequest(request);
    }
    private static Result processRequest(Request request) {
        Result result = new Result();
        result.success = false;
        result.matchCount = 0;
        result.historicalRepairContext = '';
        result.precedents = new List<HistoricalPrecedentUi>();
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
                    currentCase.Description
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
            /*
             * Subject terms represent the primary reported failure/symptom.
             * For lexical matching, at least one qualifying overlap must come
             * from the current Case Subject.
             */
            Set<String> currentSubjectTerms = tokenize(currentCase.Subject);
            currentSubjectTerms.removeAll(equipmentIdentityTerms);
            if (currentTerms.isEmpty() && String.isBlank(currentErrorCode)) {
                result.statusCode = 'MISSING_PROBLEM_CONTEXT';
                result.statusMessage = 'The current Case does not contain enough problem or symptom information to compare with historical repairs.';
                return result;
            }
            /*
             * V2 candidate retrieval:
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
             * Manufacturer is used to build a bounded candidate pool when
             * available. Eligibility is then restricted to the exact current
             * Asset or the same normalized model before problem similarity
             * and ranking are evaluated.
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
                 * V2 problem-to-problem comparison.
                 *
                 * Historical relevance is established ONLY from the original
                 * historical Case Subject and Description. Completion notes,
                 * root cause, parts used, technician notes, Maintenance Log
                 * Summary, and Work Order Subject are deliberately excluded
                 * from lexical matching. Those fields may still be returned as
                 * supporting repair evidence after a record qualifies.
                 */
                String historicalProblemContext = joinText(
                    new List<String>{
                        historicalCase == null ? null : historicalCase.Subject,
                        historicalCase == null ? null : historicalCase.Description
                    }
                );
                Set<String> historicalTerms = tokenize(historicalProblemContext);
                historicalTerms.removeAll(equipmentIdentityTerms);
                ScoredRepair scored = new ScoredRepair();
                scored.maintenanceLog = candidate;
                scored.problemSummary = buildProblemSummary(historicalCase);
                scored.sameAsset = candidate.Asset__c == currentAsset.Id;
                scored.sameManufacturer =
                    equalsIgnoreCase(candidate.Asset__r == null ? null : candidate.Asset__r.Manufacturer__c, currentAsset.Manufacturer__c);
                scored.sameModel = modelsEquivalent(
                        candidate.Asset__r == null ? null : candidate.Asset__r.Model__c,
                        currentAsset.Model__c
                    );
                scored.exactErrorMatch = !String.isBlank(currentErrorCode) &&
                    !String.isBlank(candidateErrorCode) &&
                    normalize(currentErrorCode) == normalize(candidateErrorCode);
                /*
                 * Equipment eligibility.
                 *
                 * Historical precedent must belong either to:
                 *
                 * - the exact current Asset, OR
                 * - another Asset of the same normalized model.
                 *
                 * Manufacturer-only or cross-model similarity is not sufficient
                 * for V2 Historical Repair Intelligence.
                 */
                Boolean hasEligibleEquipmentMatch = scored.sameAsset || scored.sameModel;
                if (!hasEligibleEquipmentMatch) {
                    continue;
                }
                for (String term : currentTerms) {
                    if (historicalTerms.contains(term)) {
                        scored.matchedTerms.add(term);
                    }
                }
                scored.overlapCount = scored.matchedTerms.size();
                for (String term : currentSubjectTerms) {
                    if (historicalTerms.contains(term)) {
                        scored.matchedSubjectTerms.add(term);
                    }
                }
                scored.subjectOverlapCount = scored.matchedSubjectTerms.size();
                /*
                 * Hard diagnostic relevance gate.
                 *
                 * Equipment identity does not establish problem relevance.
                 * A historical repair qualifies only when:
                 *
                 * - the exact historical error code matches, OR
                 * - at least two meaningful problem terms overlap AND at least
                 *   one of those terms appears in the current Case Subject.
                 *
                 * This prevents generic description language or unrelated
                 * repair-completion wording from qualifying a precedent.
                 */
                Boolean hasMeaningfulProblemMatch = scored.exactErrorMatch ||
                    (
                        scored.overlapCount >= 2 &&
                        scored.subjectOverlapCount >= 1
                    );
                if (!hasMeaningfulProblemMatch) {
                    continue;
                }
                /*
                 * Problem relevance dominates ranking.
                 */
                if (scored.exactErrorMatch) {
                    scored.score += 60;
                }
                scored.score += Math.min(scored.overlapCount * 15, 75);
                scored.score += Math.min(scored.subjectOverlapCount * 10, 30);
                /*
                 * Equipment relevance is a ranking signal only.
                 * A same-Asset match does not stack additional same-model and
                 * same-manufacturer bonuses.
                 */
                if (scored.sameAsset) {
                    scored.score += 12;
                } else if (scored.sameModel) {
                    scored.score += 6;
                }
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
                scoredRepairs.add(scored);
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
            result.precedents = buildHistoricalPrecedentUi(scoredRepairs, resultCount);
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
            String relevanceBasis = buildRelevanceBasis(scored);
            if (!String.isBlank(relevanceBasis)) {
                lines.add('Why relevant: ' + relevanceBasis);
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
    private static List<HistoricalPrecedentUi> buildHistoricalPrecedentUi(List<ScoredRepair> scoredRepairs, Integer resultCount) {
        List<HistoricalPrecedentUi> precedents = new List<HistoricalPrecedentUi>();
        for (Integer i = 0; i < resultCount; i++) {
            ScoredRepair scored = scoredRepairs[i];
            Maintenance_Log__c logRecord = scored.maintenanceLog;
            HistoricalPrecedentUi precedent = new HistoricalPrecedentUi();
            precedent.maintenanceLogId = logRecord.Id;
            precedent.maintenanceLogName = logRecord.Name;
            precedent.maintenanceDate = logRecord.Maintenance_Date__c;
            precedent.assetId = logRecord.Asset__c;
            precedent.manufacturer = logRecord.Asset__r == null ? null : logRecord.Asset__r.Manufacturer__c;
            precedent.model = logRecord.Asset__r == null ? null : logRecord.Asset__r.Model__c;
            precedent.serialNumber = logRecord.Asset__r == null ? null : logRecord.Asset__r.Serial_Number__c;
            precedent.workOrderId = logRecord.Work_Order__c;
            precedent.workOrderNumber = logRecord.Work_Order__r == null ? null : logRecord.Work_Order__r.WorkOrderNumber;
            precedent.sameAsset = scored.sameAsset;
            precedent.sameModel = scored.sameModel;
            precedent.whyRelevant = buildRelevanceBasis(scored);
            precedent.problemSummary = scored.problemSummary;
            precedent.successfulRepair = String.isBlank(logRecord.Summary__c) ? null : clip(logRecord.Summary__c, 600);
            precedent.rootCause = String.isBlank(logRecord.Root_Cause__c) ? null : clip(logRecord.Root_Cause__c, 500);
            precedent.partsUsed = String.isBlank(logRecord.Parts_Used__c) ? null : clip(logRecord.Parts_Used__c, 400);
            precedent.technicianNotes = String.isBlank(logRecord.Technician_Notes__c) ? null : clip(logRecord.Technician_Notes__c, 800);
            precedent.laborHours = logRecord.Labor_Hours__c;
            precedent.outcome = 'Issue resolved; no follow-up required.';
            precedents.add(precedent);
        }
        return precedents;
    }
    private static String buildProblemSummary(Case historicalCase) {
        if (historicalCase == null) {
            return null;
        }
        if (!String.isBlank(historicalCase.Description)) {
            return clip(historicalCase.Description, 600);
        }
        if (!String.isBlank(historicalCase.Subject)) {
            return clip(historicalCase.Subject, 255);
        }
        return null;
    }
    private static String buildRelevanceBasis(ScoredRepair scored) {
        List<String> basis = new List<String>();
        if (scored.exactErrorMatch) {
            basis.add('same error code');
        }
        if (scored.sameAsset) {
            basis.add('same Asset');
        } else if (scored.sameModel) {
            basis.add('same model');
        }
        if (!scored.matchedTerms.isEmpty()) {
            List<String> matchedTerms = new List<String>(scored.matchedTerms);
            matchedTerms.sort();
            Integer termsToShow = Math.min(5, matchedTerms.size());
            List<String> displayedTerms = new List<String>();
            for (Integer i = 0; i < termsToShow; i++) {
                displayedTerms.add(matchedTerms[i]);
            }
            basis.add('matching problem terms: ' + String.join(displayedTerms, ', '));
        }
        return String.join(basis, '; ');
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
    private static Boolean modelsEquivalent(String leftValue, String rightValue) {
        if (String.isBlank(leftValue) || String.isBlank(rightValue)) {
            return false;
        }
        return canonicalModel(leftValue) == canonicalModel(rightValue);
    }
    private static String canonicalModel(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        String normalizedModel = normalize(value).replace(' ', '');
        /*
         * Roland Asset data may use either the full DWX model label or
         * the shorter model label for the same physical machine:
         *
         * DWX-53DC / 53DC
         * DWX-52D  / 52D
         *
         * Remove only the leading DWX family prefix so these aliases
         * compare as the same model while 53DC and 52D remain distinct.
         */
        if (normalizedModel.startsWith('dwx')) {
            normalizedModel = normalizedModel.substring(3);
        }
        return normalizedModel;
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
