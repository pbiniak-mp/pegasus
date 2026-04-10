public with sharing class RevisionTimelineController {

	@AuraEnabled(Cacheable=true)
	public static List<RevisionWrapper> getRevisionsByOpportunity(Id opportunityId) {
		try {
			List<Design_Revision__c> revisions = DesignRevisionSelector.getRevisionsByOpportunityId(opportunityId);
			List<RevisionWrapper> result = new List<RevisionWrapper>();
			for (Design_Revision__c rev : revisions) {
				result.add(new RevisionWrapper(rev));
			}
			return result;
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	public class RevisionWrapper {
		@AuraEnabled public Id id;
		@AuraEnabled public String name;
		@AuraEnabled public String status;
		@AuraEnabled public Boolean isActive;
		@AuraEnabled public String projectWattage;
		@AuraEnabled public String systemType;
		@AuraEnabled public String roofSurface;
		@AuraEnabled public String projectNotes;
		@AuraEnabled public String createdDate;
		@AuraEnabled public String lastModifiedDate;
		@AuraEnabled public String createdByName;

		public RevisionWrapper(Design_Revision__c rev) {
			this.id = rev.Id;
			this.name = rev.Name;
			this.status = rev.Status__c;
			this.isActive = rev.Is_Active__c;
			this.projectWattage = rev.Project_Wattage_kW__c != null
				? String.valueOf(rev.Project_Wattage_kW__c)
				: '—';
			this.systemType = rev.System_Type__c != null ? rev.System_Type__c : '—';
			this.roofSurface = rev.Roof_Surface__c != null ? rev.Roof_Surface__c : '—';
			this.projectNotes = rev.Project_Notes__c;
			this.createdDate = rev.CreatedDate != null
				? rev.CreatedDate.format('d MMM yyyy, h:mm a')
				: null;
			this.lastModifiedDate = rev.LastModifiedDate != null
				? rev.LastModifiedDate.format('d MMM yyyy, h:mm a')
				: null;
			this.createdByName = rev.CreatedBy.Name;
		}
	}
}