public inherited sharing class AccountTodoSelector {
	public static List<Task> getOpenTasks(Id recordId, Boolean myTasksOnly) {
		String relatedField = contextField(recordId);
		String query =
			'SELECT ' +
			Constants.TODO_TASK_FIELDS +
			' FROM Task WHERE IsClosed = false AND ' +
			relatedField +
			' = :recordId';
		if (myTasksOnly == true) {
			query += ' AND OwnerId = :ownerId';
		}
		query += ' ORDER BY ActivityDate ASC NULLS LAST, Subject ASC, Id ASC';
		return Database.queryWithBinds(
			query,
			new Map<String, Object>{
				'recordId' => recordId,
				'ownerId' => UserInfo.getUserId()
			},
			AccessLevel.USER_MODE
		);
	}

	public static Task getTask(Id taskId, Id recordId) {
		String query =
			'SELECT ' +
			Constants.TODO_TASK_FIELDS +
			' FROM Task WHERE Id = :taskId AND ' +
			contextField(recordId) +
			' = :recordId';
		List<Task> tasks = Database.queryWithBinds(
			query,
			new Map<String, Object>{ 'taskId' => taskId, 'recordId' => recordId },
			AccessLevel.USER_MODE
		);
		return tasks.isEmpty() ? null : tasks[0];
	}

	public static Id getContactAccountId(Id contactId) {
		List<Contact> contacts = [
			SELECT AccountId
			FROM Contact
			WHERE Id = :contactId
			WITH USER_MODE
		];
		return contacts.isEmpty() ? null : contacts[0].AccountId;
	}

	private static String contextField(Id recordId) {
		if (recordId != null) {
			Schema.SObjectType recordType = recordId.getSObjectType();
			if (recordType == Account.SObjectType)
				return 'AccountId';
			if (recordType == Contact.SObjectType)
				return 'WhoId';
			if (recordType == Opportunity.SObjectType)
				return 'WhatId';
		}
		throw new IllegalArgumentException(Constants.TODO_INVALID_CONTEXT);
	}
}
