public inherited sharing class AccountTodoService {
	public static List<Task> getOpenTasks(Id recordId, Boolean myTasksOnly) {
		return AccountTodoSelector.getOpenTasks(recordId, myTasksOnly);
	}

	public static void completeTask(Id taskId, Id recordId) {
		Task source = requireTask(taskId, recordId);
		if (source.IsClosed)
			throw new IllegalArgumentException(Constants.TODO_ALREADY_CLOSED);
		// Update only Status so unrelated fields do not need edit access.
		Database.update(
			new Task(Id = source.Id, Status = Constants.TODO_STATUS_COMPLETED),
			AccessLevel.USER_MODE
		);
	}

	public static Id createTask(
		Id recordId,
		String subject,
		String taskType,
		Date dueDate
	) {
		Task activity = newActivity(
			subject,
			taskType,
			dueDate,
			UserInfo.getUserId()
		);
		if (recordId == null)
			throw new IllegalArgumentException(Constants.TODO_INVALID_CONTEXT);
		Schema.SObjectType recordType = recordId.getSObjectType();
		if (
			recordType == Account.SObjectType ||
			recordType == Opportunity.SObjectType
		) {
			activity.WhatId = recordId;
		} else if (recordType == Contact.SObjectType) {
			activity.WhoId = recordId;
			activity.WhatId = AccountTodoSelector.getContactAccountId(recordId);
		} else {
			throw new IllegalArgumentException(Constants.TODO_INVALID_CONTEXT);
		}
		Database.insert(activity, AccessLevel.USER_MODE);
		return activity.Id;
	}

	public static Id scheduleNext(
		Id taskId,
		Id recordId,
		String subject,
		String taskType,
		Date dueDate,
		Id ownerId
	) {
		Task source = requireTask(taskId, recordId);
		if (!source.IsClosed)
			throw new IllegalArgumentException(Constants.TODO_NOT_CLOSED);
		Task activity = newActivity(subject, taskType, dueDate, ownerId);
		// AccountId is derived by Salesforce. Keep both original relationships.
		activity.WhoId = source.WhoId;
		activity.WhatId = source.WhatId;
		Database.insert(activity, AccessLevel.USER_MODE);
		return activity.Id;
	}

	public static List<Map<String, String>> getTaskTypeOptions() {
		Schema.DescribeFieldResult field = Task.Task_Type__c.getDescribe();
		if (!field.isAccessible())
			throw new IllegalArgumentException(Constants.TODO_TYPE_INACCESSIBLE);
		List<Map<String, String>> options = new List<Map<String, String>>();
		for (Schema.PicklistEntry entry : field.getPicklistValues()) {
			if (entry.isActive())
				options.add(
					new Map<String, String>{
						'label' => entry.getLabel(),
						'value' => entry.getValue()
					}
				);
		}
		return options;
	}

	private static Task requireTask(Id taskId, Id recordId) {
		Task source = AccountTodoSelector.getTask(taskId, recordId);
		if (source == null)
			throw new IllegalArgumentException(Constants.TODO_TASK_UNAVAILABLE);
		return source;
	}

	private static Task newActivity(
		String subject,
		String taskType,
		Date dueDate,
		Id ownerId
	) {
		if (String.isBlank(subject))
			throw new IllegalArgumentException(Constants.TODO_SUBJECT_REQUIRED);
		Id assignedOwner = ownerId == null ? UserInfo.getUserId() : ownerId;
		if (assignedOwner.getSObjectType() != User.SObjectType) {
			throw new IllegalArgumentException(Constants.TODO_OWNER_INVALID);
		}
		Task activity = new Task(
			Subject = subject.trim(),
			ActivityDate = dueDate,
			OwnerId = assignedOwner,
			Status = Constants.TODO_STATUS_OPEN,
			Priority = Constants.TODO_PRIORITY_NORMAL
		);
		// Leave an optional blank type unset, respecting field access on insert.
		if (String.isNotBlank(taskType))
			activity.Task_Type__c = taskType;
		return activity;
	}
}
