@IsTest
private class LeadSelectorTest {
	@IsTest
	static void getOwnersByIds_returnsOwner() {
		Lead lead = new Lead(LastName = 'Owner Test', Company = 'Owner Co');
		insert lead;

		List<Lead> result = LeadSelector.getOwnersByIds(new Set<Id>{ lead.Id });

		Assert.areEqual(1, result.size());
		Assert.areEqual(UserInfo.getUserId(), result[0].OwnerId);
	}
}
