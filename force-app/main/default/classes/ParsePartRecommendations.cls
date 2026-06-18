public with sharing class ParsePartRecommendations {
    public class Request {
        @InvocableVariable(required=true)
        public String recommendedParts;
    }

    public class Result {
        @InvocableVariable
        public String name;

        @InvocableVariable
        public Integer quantity;
    }

    private class PartsWrapper {
        public list<PartItem> parts;
    }

    private class PartItem {
        public String Name;
        public Integer quantity;
    }

    @InvocableMethod(label='Parse Part Recommendations')
    public static List<Result> parseParts(List<Request> requests) {
        List<Result> results = new List<Result>();

        if(requests == null || requests.isEmpty()) {
            return results;
        }

        String rawInput = requests[0].recommendedParts;

        if(String.isBlank(rawInput)) {
            return results;
        }

        try {
            PartsWrapper wrapper = (PartsWrapper) JSON.deserialize(rawInput, PartsWrapper.class);

            if(wrapper == null || wrapper.parts == null) {
                return results;
            }

            for(PartItem item : wrapper.parts) {
                if(item == null || String.isBlank(item.Name)) {
                    continue;
                }

                Result r = new Result();
                r.Name = item.Name.trim();
                r.quantity = item.quantity == null || item.quantity <=0 ? 1 : item.quantity;
                results.add(r);
            }
        } catch (Exception e) {
            Result fallback = new Result();
            fallback.Name = rawInput.trim();
            fallback.quantity = 1;
            results.add(fallback);
        }

        return results;
    }
}