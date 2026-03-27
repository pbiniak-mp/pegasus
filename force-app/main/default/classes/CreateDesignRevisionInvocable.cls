public with sharing class CreateDesignRevisionInvocable {

	public class Request {
		@InvocableVariable(Label='Current Revision Id' Required=true)
		public Id revisionId;

		@InvocableVariable(Label='Revision Reason' Required=true)
		public String revisionReason;

		@InvocableVariable(Label='Project Notes' Required=false)
		public String projectNotes;
	}

	public class Result {
		@InvocableVariable(Label='New Revision Id')
		public Id newRevisionId;
	}

	@InvocableMethod(Label='Create New Design Revision' Category='Design Revision')
	public static List<Result> createNewRevision(List<Request> requests) {
		List<Result> results = new List<Result>();
		for (Request req : requests) {
			Result res = new Result();
			res.newRevisionId = DesignRevisionService.createNewRevision(
				req.revisionId,
				req.revisionReason,
				req.projectNotes
			);
			results.add(res);
		}
		return results;
	}
}