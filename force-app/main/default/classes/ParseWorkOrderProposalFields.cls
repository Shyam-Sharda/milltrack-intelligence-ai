public with sharing class ParseWorkOrderProposalFields {
    public class Request {
        @InvocableVariable(required = true)
        public String proposalText;
    }

    public class Response {
        @InvocableVariable
        public String problemSummary;

        @InvocableVariable
        public String recommendedSolution;

        @InvocableVariable
        public String technicianNotes;

        @InvocableVariable
        public String recommendedParts;

        @InvocableVariable
        public Boolean previousFailure;

        @InvocableVariable
        public String priority;
    }

    @InvocableMethod(
        label = 'Parse Work Order Proposal Fields'
        description = 'Parses structured AI Work Order proposal text into Flow-friendly field outputs')
    public static List<Response> parseProposalFields(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for(Request req: requests) {
            Response res = new Response();

            String textToParse = req != null && req.proposalText != null ? req.proposalText : '';

            res.problemSummary = extractSection(textToParse, 'PROBLEM SUMMARY', 
                new List<String>{'RECOMMENDED SOLUTION', 'TECHNICIAN NOTES', 'RECOMMENDED PARTS', 'PREVIOUS FAILURE', 'PRIORITY'});
            
            res.recommendedSolution = extractSection(textToParse, 'RECOMMENDED SOLUTION',
                new List<String>{'TECHNICIAN NOTES', 'RECOMMENDED PARTS', 'PREVIOUS FAILURE', 'PRIORITY'});
            
            res.technicianNotes = extractSection(textToParse, 'TECHNICIAN NOTES',
                new List<String>{'RECOMMENDED PARTS', 'PREVIOUS FAILURE', 'PRIORITY'});
            
            res.recommendedParts = extractSection(textToParse, 'RECOMMENDED PARTS',
                new List<String>{'PREVIOUS FAILURE', 'PRIORITY'});
            
            String previousFailureText = extractSection(textToParse, 'PREVIOUS FAILURE', new List<String>{'PRIORITY'});

            res.previousFailure = previousFailureText != null && previousFailureText.trim().equalsIgnoreCase('true');

            String priorityText = extractSection(textToParse, 'PRIORITY', new List<String>());
            
            res.priority = normalizePriority(priorityText);

            responses.add(res);
        }

        return responses;
    }

    private static String extractSection(String fullText, String sectionName, List<String> followingSectionNames) {
        if (String.isBlank(fullText) || String.isBlank(sectionName)) {
            return '';
        }

        String normalizedText = fullText.replace('\r\n', '\n').replace('\r', '\n');

        Pattern startPattern = Pattern.compile('(?i)(^|\\n)\\s*' + Pattern.quote(sectionName) + '\\s*:\\s*');

        Matcher startMatcher = startPattern.matcher(normalizedText);

        if(!startMatcher.find()) {
            return '';
        }

        Integer contentStart = startMatcher.end();
        Integer contentEnd = normalizedText.length();

        for(String nextSection: followingSectionNames) {
            Pattern endPattern = Pattern.compile('(?i)(^|\\n)\\s*' + Pattern.quote(nextSection) + '\\s*:\\s*');

            Matcher endMatcher = endPattern.matcher(normalizedText);

            if(endMatcher.find(contentStart)) {
                contentEnd = Math.min(contentEnd, endMatcher.start());
            }
        }

        String sectionValue = normalizedText.substring(contentStart, contentEnd).trim();

        return sectionValue;
    }

    private static String normalizePriority(String priorityText) {
        if (String.isBlank(priorityText)) {
            return '';
        }

        String cleaned = priorityText.trim();

        if(cleaned.equalsIgnoreCase('Low')) {
            return 'Low';
        }
        if (cleaned.equalsIgnoreCase('Medium')) {
            return 'Medium';
        }
        if (cleaned.equalsIgnoreCase('High')) {
            return 'High';
        }
        if (cleaned.equalsIgnoreCase('Critical')) {
            return 'Critical';
        }

        return '';
    }
}