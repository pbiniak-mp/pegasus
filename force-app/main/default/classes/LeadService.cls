public with sharing class LeadService {

	private static final String CLASS_NAME = 'LeadService';
	private static final String ERR_HANDLE_CONVERTED = 'Failed to process address propagation for converted Leads';

	public static void handleConvertedLeads(List<Lead> newList, Map<Id, Lead> oldMap) {
		if (newList == null || newList.isEmpty() || oldMap == null) return;

		List<Lead> justConverted = new List<Lead>();
		for (Lead l : newList) {
			Lead oldLead = oldMap.get(l.Id);
			if (oldLead == null) continue;
			if (l.IsConverted && !oldLead.IsConverted && l.ConvertedOpportunityId != null) {
				justConverted.add(l);
			}
		}

		if (justConverted.isEmpty()) return;

		try {
			propagateAddress(justConverted);
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'handleConvertedLeads',
				ERR_HANDLE_CONVERTED + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			throw e;
		}
	}

	private static void propagateAddress(List<Lead> justConverted) {
		Set<Id> accountIds = new Set<Id>();
		for (Lead l : justConverted) {
			if (l.ConvertedAccountId != null) accountIds.add(l.ConvertedAccountId);
		}

		Map<Id, Account> accountsById = accountIds.isEmpty()
			? new Map<Id, Account>()
			: new Map<Id, Account>(AccountSelector.getAccountsByIds(accountIds));

		List<Opportunity> opportunityUpdates = new List<Opportunity>();
		List<Account> accountUpdates = new List<Account>();

		for (Lead l : justConverted) {
			opportunityUpdates.add(buildOpportunityAddressUpdate(l));

			if (l.ConvertedAccountId == null) continue;
			Account convertedAccount = accountsById.get(l.ConvertedAccountId);
			if (convertedAccount == null) continue;
			if (isNewlyCreatedAccount(convertedAccount)) {
				accountUpdates.add(buildAccountResetForNewConversion(convertedAccount.Id));
			}
		}

		if (!accountUpdates.isEmpty()) {
			update accountUpdates;
		}
		if (!opportunityUpdates.isEmpty()) {
			update opportunityUpdates;
		}
	}

	private static Opportunity buildOpportunityAddressUpdate(Lead l) {
		return new Opportunity(
			Id = l.ConvertedOpportunityId,
			Project_Street__c = l.Street,
			Project_City__c = l.City,
			Project_State__c = l.State,
			Project_State_Code__c = String.isNotBlank(l.StateCode) ? l.StateCode : StateCodeService.getCode(l.State),
			Project_PostalCode__c = l.PostalCode,
			Project_Country__c = l.Country
		);
	}

	private static Account buildAccountResetForNewConversion(Id accountId) {
		return new Account(
			Id = accountId,
			Created_From_Lead_Conversion__c = true,
			BillingStreet = null,
			BillingCity = null,
			BillingState = null,
			BillingPostalCode = null,
			BillingCountry = null,
			BillingLatitude = null,
			BillingLongitude = null
		);
	}

	// Account is "newly created during this Lead conversion" if its CreatedDate
	// is within the configured window of now(). Lead conversion creates the
	// Account immediately before the Lead.afterUpdate trigger fires in the same
	// transaction, so the gap is milliseconds; the window absorbs any skew.
	// Lead.ConvertedDate isn't used because it is Date-typed, not Datetime.
	private static Boolean isNewlyCreatedAccount(Account a) {
		if (a == null || a.CreatedDate == null) return false;
		Long createdMs = a.CreatedDate.getTime();
		Long nowMs = Datetime.now().getTime();
		Long windowMs = (Long) Constants.LEAD_CONVERSION_NEW_ACCOUNT_WINDOW_SECONDS * 1000L;
		return nowMs - createdMs <= windowMs;
	}
}
