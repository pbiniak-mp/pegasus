public with sharing class DesignRevisionHierarchyController {

    public class RevisionNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String recordUrl;
        @AuraEnabled public String revisionNumber;
        @AuraEnabled public String revisionReason;
        @AuraEnabled public String projectNotes;
        @AuraEnabled public List<RevisionNode> children;

        public RevisionNode(Design_Revision__c record) {
            this.id = record.Id;
            this.name = record.Name;
            this.recordUrl = Constants.DESIGN_REVISION_RECORD_URL_BASE + record.Id + Constants.RECORD_URL_VIEW_SUFFIX;
            this.revisionNumber = record.Revision_Number__c;
            this.revisionReason = record.Revision_Reason__c;
            this.projectNotes = record.Project_Notes__c;
            this.children = new List<RevisionNode>();
        }
    }

    @AuraEnabled(Cacheable=true)
    public static List<RevisionNode> getRevisionHierarchy(Id opportunityId) {
        List<Design_Revision__c> records = DesignRevisionSelector.getHierarchyFieldsByOpportunityId(opportunityId);

        Map<Id, RevisionNode> nodeById = new Map<Id, RevisionNode>();
        for (Design_Revision__c record : records) {
            nodeById.put(record.Id, new RevisionNode(record));
        }

        List<RevisionNode> roots = new List<RevisionNode>();
        for (Design_Revision__c record : records) {
            RevisionNode node = nodeById.get(record.Id);
            if (record.Parent_Revision__c != null && nodeById.containsKey(record.Parent_Revision__c)) {
                nodeById.get(record.Parent_Revision__c).children.add(node);
            } else {
                roots.add(node);
            }
        }

        return roots;
    }
}
