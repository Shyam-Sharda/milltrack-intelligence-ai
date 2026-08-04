public with sharing class ParseWorkOrderProposalFields {
    public class Request {
        @InvocableVariable(required=true)
        public String proposalText;
    }

    public class Response {
        @InvocableVariable
        public String problemSummary;

        @InvocableVariable
        public String recommendedFixSummary;

        @InvocableVariable
        public String recommendedSolution;

        @InvocableVariable
        public String technicianNotes;

        @InvocableVariable
        public String recommendedTools;

        @InvocableVariable
        public String recommendedParts;

        // Retained for backward compatibility with legacy structured prompts.
        @InvocableVariable
        public String recommendedPartsJson;

        @InvocableVariable
        public Boolean previousFailure;

        @InvocableVariable
        public String priority;
    }

    @InvocableMethod(
        label='Parse Work Order Proposal Fields'
        description='Parses structured AI Work Order proposal text into Flow-friendly field outputs'
    )
    public static List<Response> parseProposalFields(
        List<Request> requests
    ) {
        List<Response> responses = new List<Response>();

        if (requests == null) {
            return responses;
        }

        for (Request req : requests) {
            Response res = new Response();
            String textToParse =
                req != null && req.proposalText != null
                ? req.proposalText
                : '';

            res.problemSummary = extractSection(
                textToParse,
                'PROBLEM SUMMARY',
                new List<String>{
                    'RECOMMENDED FIX SUMMARY',
                    'RECOMMENDED SOLUTION',
                    'TECHNICIAN NOTES',
                    'RECOMMENDED TOOLS',
                    'RECOMMENDED PARTS',
                    'PREVIOUS FAILURE',
                    'PRIORITY'
                }
            );

            res.recommendedFixSummary = extractSection(
                textToParse,
                'RECOMMENDED FIX SUMMARY',
                new List<String>{
                    'RECOMMENDED SOLUTION',
                    'TECHNICIAN NOTES',
                    'RECOMMENDED TOOLS',
                    'RECOMMENDED PARTS',
                    'PREVIOUS FAILURE',
                    'PRIORITY'
                }
            );

            res.recommendedSolution = extractSection(
                textToParse,
                'RECOMMENDED SOLUTION',
                new List<String>{
                    'TECHNICIAN NOTES',
                    'RECOMMENDED TOOLS',
                    'RECOMMENDED PARTS',
                    'PREVIOUS FAILURE',
                    'PRIORITY'
                }
            );

            res.technicianNotes = extractSection(
                textToParse,
                'TECHNICIAN NOTES',
                new List<String>{
                    'RECOMMENDED TOOLS',
                    'RECOMMENDED PARTS',
                    'PREVIOUS FAILURE',
                    'PRIORITY'
                }
            );

            res.recommendedTools = extractSection(
                textToParse,
                'RECOMMENDED TOOLS',
                new List<String>{
                    'RECOMMENDED PARTS',
                    'PREVIOUS FAILURE',
                    'PRIORITY'
                }
            );

            String rawRecommendedParts = extractSection(
                textToParse,
                'RECOMMENDED PARTS',
                new List<String>{
                    'PREVIOUS FAILURE',
                    'PRIORITY'
                }
            );
            populateRecommendedParts(res, rawRecommendedParts);

            String previousFailureText = extractSection(
                textToParse,
                'PREVIOUS FAILURE',
                new List<String>{'PRIORITY'}
            );
            res.previousFailure =
                previousFailureText != null &&
                previousFailureText.trim().equalsIgnoreCase('true');

            String priorityText = extractSection(
                textToParse,
                'PRIORITY',
                new List<String>()
            );
            res.priority = normalizePriority(priorityText);

            responses.add(res);
        }

        return responses;
    }

    /**
     * Plain text is now the primary Recommended Parts format. Legacy JSON is
     * still accepted so older prompt versions do not break active automation.
     */
    private static void populateRecommendedParts(
        Response response,
        String rawValue
    ) {
        if (String.isBlank(rawValue)) {
            response.recommendedParts = '';
            response.recommendedPartsJson = '';
            return;
        }

        String cleanedValue = normalizeRecommendedPartsJson(rawValue);

        if (isStructuredJson(cleanedValue)) {
            response.recommendedPartsJson = cleanedValue;
            response.recommendedParts =
                formatRecommendedPartsForDisplay(cleanedValue);
        } else {
            response.recommendedParts = rawValue.trim();
            response.recommendedPartsJson = '';
        }
    }

    /**
     * Removes optional Markdown code fences around legacy JSON.
     */
    private static String normalizeRecommendedPartsJson(String rawValue) {
        if (String.isBlank(rawValue)) {
            return '';
        }

        String cleaned = rawValue.trim();
        cleaned = cleaned.replaceAll(
            '(?i)^\\s*```json\\s*',
            ''
        );
        cleaned = cleaned.replaceAll(
            '(?i)^\\s*```\\s*',
            ''
        );
        cleaned = cleaned.replaceAll(
            '\\s*```\\s*$',
            ''
        );
        return cleaned.trim();
    }

    private static Boolean isStructuredJson(String value) {
        if (String.isBlank(value)) {
            return false;
        }

        try {
            Object parsedValue = JSON.deserializeUntyped(value);
            return
                parsedValue instanceof Map<String, Object> ||
                parsedValue instanceof List<Object>;
        } catch (Exception ex) {
            return false;
        }
    }

    /**
     * Converts legacy structured JSON into readable manager-facing text.
     */
    private static String formatRecommendedPartsForDisplay(
        String jsonText
    ) {
        if (String.isBlank(jsonText)) {
            return '';
        }

        try {
            Object parsedJson = JSON.deserializeUntyped(jsonText);
            List<Object> partItems = new List<Object>();

            if (parsedJson instanceof Map<String, Object>) {
                Map<String, Object> root =
                    (Map<String, Object>) parsedJson;
                Object partsValue = root.get('parts');

                if (partsValue instanceof List<Object>) {
                    partItems = (List<Object>) partsValue;
                }
            } else if (parsedJson instanceof List<Object>) {
                partItems = (List<Object>) parsedJson;
            }

            List<String> readableParts = new List<String>();

            for (Object partItem : partItems) {
                if (!(partItem instanceof Map<String, Object>)) {
                    continue;
                }

                Map<String, Object> part =
                    (Map<String, Object>) partItem;
                String partName = getStringValue(part, 'name');
                String quantity = getQuantityValue(part);

                if (String.isBlank(partName)) {
                    continue;
                }

                String displayLine = partName;

                if (!String.isBlank(quantity)) {
                    displayLine += ' â€” Quantity: ' + quantity;
                }

                readableParts.add(displayLine);
            }

            return String.join(readableParts, '\n');
        } catch (Exception ex) {
            // Defensive fallback: never replace useful AI text with an error.
            return jsonText.trim();
        }
    }

    private static String getStringValue(
        Map<String, Object> values,
        String key
    ) {
        if (
            values == null ||
            !values.containsKey(key) ||
            values.get(key) == null
        ) {
            return '';
        }

        return String.valueOf(values.get(key)).trim();
    }

    private static String getQuantityValue(
        Map<String, Object> part
    ) {
        if (part == null) {
            return '';
        }

        Object quantityValue;

        if (part.containsKey('quantity')) {
            quantityValue = part.get('quantity');
        } else if (part.containsKey('quantityNeeded')) {
            quantityValue = part.get('quantityNeeded');
        } else if (part.containsKey('quantity_needed')) {
            quantityValue = part.get('quantity_needed');
        }

        if (quantityValue == null) {
            return '';
        }

        String quantityText = String.valueOf(quantityValue).trim();

        if (quantityText.endsWith('.0')) {
            quantityText = quantityText.substring(
                0,
                quantityText.length() - 2
            );
        }

        return quantityText;
    }

    private static String extractSection(
        String fullText,
        String sectionName,
        List<String> followingSectionNames
    ) {
        if (
            String.isBlank(fullText) ||
            String.isBlank(sectionName)
        ) {
            return '';
        }

        String normalizedText = fullText
            .replace('\r\n', '\n')
            .replace('\r', '\n');

        Pattern startPattern = Pattern.compile(
            '(?i)(^|\\n)\\s*' +
            Pattern.quote(sectionName) +
            '\\s*:\\s*'
        );
        Matcher startMatcher = startPattern.matcher(normalizedText);

        if (!startMatcher.find()) {
            return '';
        }

        Integer contentStart = startMatcher.end();
        Integer contentEnd = normalizedText.length();

        for (String nextSection : followingSectionNames) {
            Pattern endPattern = Pattern.compile(
                '(?i)(^|\\n)\\s*' +
                Pattern.quote(nextSection) +
                '\\s*:\\s*'
            );
            Matcher endMatcher = endPattern.matcher(normalizedText);

            if (endMatcher.find(contentStart)) {
                contentEnd = Math.min(
                    contentEnd,
                    endMatcher.start()
                );
            }
        }

        return normalizedText
            .substring(contentStart, contentEnd)
            .trim();
    }

    private static String normalizePriority(String priorityText) {
        if (String.isBlank(priorityText)) {
            return '';
        }

        String cleaned = priorityText.trim();

        if (cleaned.equalsIgnoreCase('Low')) {
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