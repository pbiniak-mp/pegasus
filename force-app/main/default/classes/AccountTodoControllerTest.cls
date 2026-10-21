@IsTest
private class AccountTodoControllerTest {
	@TestSetup
	static void setup() {
		User teammate = new User(
			Alias = 'todotest',
			LastName = 'Todo Teammate',
			Email = 'account-todo@example.invalid',
			Username = 'account-todo.' +
				UserInfo.getOrganizationId() +
				'.' +
				DateTime.now().getTime() +
				'@example.invalid',
			CommunityNickname = 'todo' + DateTime.now().getTime(),
			ProfileId = UserInfo.getProfileId(),
			TimeZoneSidKey = 'America/Los_Angeles',
			LocaleSidKey = 'en_US',
			EmailEncodingKey = 'UTF-8',
			LanguageLocaleKey = 'en_US'
		);
		insert teammate;
		// Separate setup and business DML, and give the running user visibility of both owners.
		System.runAs(new User(Id = UserInfo.getUserId())) {
			Account account = new Account(Name = 'Todo Account');
			Account other = new Account(Name = 'Other Todo Account');
			insert new List<Account>{ account, other };
			Contact contact = new Contact(
				LastName = 'Todo Contact',
				AccountId = account.Id
			);
			insert contact;
			TriggerHandler.bypass(Constants.OPPORTUNITY_HANDLER_NAME);
			Opportunity opportunity = new Opportunity(
				Name = 'Todo Opportunity',
				AccountId = account.Id,
				StageName = 'Design',
				CloseDate = Date.today().addDays(30)
			);
			insert opportunity;
			TriggerHandler.clearBypass(Constants.OPPORTUNITY_HANDLER_NAME);
			insert new List<Task>{
				new Task(
					Subject = 'Overdue call',
					WhatId = account.Id,
					ActivityDate = Date.today().addDays(-2),
					Status = Constants.TODO_STATUS_OPEN,
					Priority = 'High',
					Task_Type__c = 'Call'
				),
				new Task(
					Subject = 'Contact today',
					WhoId = contact.Id,
					ActivityDate = Date.today(),
					Status = Constants.TODO_STATUS_OPEN,
					Priority = Constants.TODO_PRIORITY_NORMAL,
					Task_Type__c = 'Text Message',
					Description = 'Contact-only task'
				),
				new Task(
					Subject = 'Opportunity upcoming',
					WhatId = opportunity.Id,
					WhoId = contact.Id,
					ActivityDate = Date.today().addDays(3),
					OwnerId = teammate.Id,
					Status = Constants.TODO_STATUS_OPEN,
					Priority = Constants.TODO_PRIORITY_NORMAL,
					Task_Type__c = 'Web Meeting'
				),
				new Task(
					Subject = 'Undated task',
					WhatId = account.Id,
					Status = Constants.TODO_STATUS_OPEN,
					Priority = Constants.TODO_PRIORITY_NORMAL
				),
				new Task(
					Subject = 'Closed task',
					WhatId = account.Id,
					Status = Constants.TODO_STATUS_COMPLETED,
					Priority = Constants.TODO_PRIORITY_NORMAL
				),
				new Task(
					Subject = 'Unrelated task',
					WhatId = other.Id,
					Status = Constants.TODO_STATUS_OPEN,
					Priority = Constants.TODO_PRIORITY_NORMAL
				)
			};
		}
	}

	private static Id accountId() {
		return [SELECT Id FROM Account WHERE Name = 'Todo Account' LIMIT 1].Id;
	}

	@IsTest
	static void allTasksIncludeAccountContactAndOpportunityInDateOrder() {
		Test.startTest();
		List<Task> tasks = AccountTodoController.getOpenTasks(accountId(), false);
		Test.stopTest();
		Assert.areEqual(
			4,
			tasks.size(),
			'Include related contact and opportunity tasks, excluding closed and unrelated tasks'
		);
		Assert.areEqual('Overdue call', tasks[0].Subject);
		Assert.areEqual('Contact today', tasks[1].Subject);
		Assert.areEqual('Opportunity upcoming', tasks[2].Subject);
		Assert.areEqual('Undated task', tasks[3].Subject);
		Assert.areEqual('High', tasks[0].Priority);
		Assert.areEqual('Text Message', tasks[1].Task_Type__c);
		Assert.areEqual('Contact-only task', tasks[1].Description);
		Assert.areEqual('Todo Contact', tasks[1].Who.Name);
		Assert.areEqual('Todo Opportunity', tasks[2].What.Name);
		Assert.isNotNull(tasks[2].Owner.Name);
	}

	@IsTest
	static void myTasksFilterUsesCurrentUser() {
		Test.startTest();
		List<Task> tasks = AccountTodoController.getOpenTasks(accountId(), true);
		Test.stopTest();
		Assert.areEqual(3, tasks.size());
		for (Task task : tasks)
			Assert.areEqual(UserInfo.getUserId(), task.OwnerId);
	}

	@IsTest
	static void contactAndOpportunityScopes() {
		Id contactId = [SELECT Id FROM Contact LIMIT 1].Id;
		Id opportunityId = [SELECT Id FROM Opportunity LIMIT 1].Id;
		Test.startTest();
		List<Task> contactTasks = AccountTodoController.getOpenTasks(
			contactId,
			false
		);
		List<Task> opportunityTasks = AccountTodoController.getOpenTasks(
			opportunityId,
			false
		);
		Test.stopTest();
		Assert.areEqual(2, contactTasks.size());
		Assert.areEqual(1, opportunityTasks.size());
		Assert.areEqual(opportunityId, opportunityTasks[0].WhatId);
		Assert.areEqual(
			0,
			AccountTodoController.getOpenTasks(opportunityId, true).size()
		);
	}

	@IsTest
	static void completeAndScheduleNextPreservesRelationshipsAndOwner() {
		Id contextId = accountId();
		Task original = [
			SELECT Id, WhoId, WhatId
			FROM Task
			WHERE Subject = 'Opportunity upcoming'
			LIMIT 1
		];
		Test.startTest();
		AccountTodoController.completeTask(original.Id, contextId);
		Id nextId = AccountTodoController.scheduleNext(
			original.Id,
			contextId,
			'Next meeting',
			'First Meeting',
			Date.today().addDays(1),
			UserInfo.getUserId()
		);
		Test.stopTest();
		Task completed = [
			SELECT Status, IsClosed
			FROM Task
			WHERE Id = :original.Id
		];
		Task next = [
			SELECT
				AccountId,
				WhoId,
				WhatId,
				Subject,
				Task_Type__c,
				ActivityDate,
				OwnerId,
				Status,
				IsClosed
			FROM Task
			WHERE Id = :nextId
		];
		Assert.areEqual(Constants.TODO_STATUS_COMPLETED, completed.Status);
		Assert.isTrue(completed.IsClosed);
		Assert.areEqual(original.WhoId, next.WhoId);
		Assert.areEqual(original.WhatId, next.WhatId);
		Assert.areEqual(contextId, next.AccountId);
		Assert.areEqual('Next meeting', next.Subject);
		Assert.areEqual('First Meeting', next.Task_Type__c);
		Assert.areEqual(Date.today().addDays(1), next.ActivityDate);
		Assert.areEqual(UserInfo.getUserId(), next.OwnerId);
		Assert.areEqual(Constants.TODO_STATUS_OPEN, next.Status);
		Assert.isFalse(next.IsClosed);
	}

	@IsTest
	static void contactOnlyFollowUpKeepsDerivedAccountAndDefaultsOwner() {
		Task original = [
			SELECT Id, WhoId
			FROM Task
			WHERE Subject = 'Contact today'
			LIMIT 1
		];
		AccountTodoController.completeTask(original.Id, original.WhoId);
		Id nextId = AccountTodoController.scheduleNext(
			original.Id,
			original.WhoId,
			'Contact again',
			null,
			null,
			null
		);
		Task next = [
			SELECT AccountId, WhoId, WhatId, ActivityDate, OwnerId
			FROM Task
			WHERE Id = :nextId
		];
		Assert.areEqual(accountId(), next.AccountId);
		Assert.areEqual(original.WhoId, next.WhoId);
		Assert.isNull(next.WhatId, 'Preserve a contact-only source relationship');
		Assert.isNull(next.ActivityDate);
		Assert.areEqual(UserInfo.getUserId(), next.OwnerId);
	}

	@IsTest
	static void completeWithoutFollowUpCreatesNothing() {
		Id contextId = accountId();
		Task original = [
			SELECT Id
			FROM Task
			WHERE Subject = 'Overdue call'
			LIMIT 1
		];
		Integer countBefore = [SELECT COUNT() FROM Task];
		AccountTodoController.completeTask(original.Id, contextId);
		Assert.areEqual(countBefore, [SELECT COUNT() FROM Task]);
		Assert.areEqual(
			3,
			AccountTodoController.getOpenTasks(contextId, false).size()
		);
	}

	@IsTest
	static void createForAllSupportedRecordTypes() {
		Id contextId = accountId();
		Id contactId = [SELECT Id FROM Contact LIMIT 1].Id;
		Id opportunityId = [SELECT Id FROM Opportunity LIMIT 1].Id;
		Test.startTest();
		Set<Id> ids = new Set<Id>{
			AccountTodoController.createTask(
				contextId,
				'  Account follow-up  ',
				'Call',
				Date.today()
			),
			AccountTodoController.createTask(
				contactId,
				'Contact follow-up',
				null,
				null
			),
			AccountTodoController.createTask(
				opportunityId,
				'Opportunity follow-up',
				'Trial',
				Date.today().addDays(2)
			)
		};
		Test.stopTest();
		Map<String, Task> bySubject = new Map<String, Task>();
		for (Task task : [
			SELECT
				Subject,
				AccountId,
				WhoId,
				WhatId,
				OwnerId,
				Status,
				IsClosed,
				ActivityDate
			FROM Task
			WHERE Id IN :ids
		]) {
			bySubject.put(task.Subject, task);
			Assert.areEqual(contextId, task.AccountId);
			Assert.areEqual(Constants.TODO_STATUS_OPEN, task.Status);
			Assert.areEqual(UserInfo.getUserId(), task.OwnerId);
			Assert.isFalse(task.IsClosed);
		}
		Assert.areEqual(contextId, bySubject.get('Account follow-up').WhatId);
		Assert.areEqual(contactId, bySubject.get('Contact follow-up').WhoId);
		Assert.areEqual(contextId, bySubject.get('Contact follow-up').WhatId);
		Assert.isNull(bySubject.get('Contact follow-up').ActivityDate);
		Assert.areEqual(
			opportunityId,
			bySubject.get('Opportunity follow-up').WhatId
		);
	}

	@IsTest
	static void typesAreActiveMetadataValues() {
		List<Map<String, String>> options = AccountTodoController.getTaskTypeOptions();
		Set<String> values = new Set<String>();
		for (Map<String, String> option : options) {
			Assert.isNotNull(option.get('label'));
			values.add(option.get('value'));
		}
		Assert.isTrue(values.contains('Call'));
		Assert.isTrue(values.contains('Trial'));
	}

	@IsTest
	static void clearErrorsForInvalidContextSubjectAndPicklist() {
		Id contextId = accountId();
		Id unsupportedId = UserInfo.getUserId();
		for (Id invalidId : new List<Id>{ null, unsupportedId }) {
			try {
				AccountTodoController.getOpenTasks(invalidId, false);
				Assert.fail('An unsupported record must fail');
			} catch (AuraHandledException error) {
				Assert.isTrue(
					error.getMessage().contains(Constants.TODO_INVALID_CONTEXT)
				);
			}
			try {
				AccountTodoController.createTask(
					invalidId,
					'Invalid context',
					null,
					null
				);
				Assert.fail('An unsupported record must fail on create');
			} catch (AuraHandledException error) {
				Assert.isTrue(
					error.getMessage().contains(Constants.TODO_INVALID_CONTEXT)
				);
			}
		}
		try {
			AccountTodoController.createTask(contextId, '  ', null, null);
			Assert.fail('Blank subject must fail');
		} catch (AuraHandledException error) {
			Assert.isTrue(
				error.getMessage().contains(Constants.TODO_SUBJECT_REQUIRED)
			);
		}
		try {
			AccountTodoController.createTask(
				contextId,
				'Bad type',
				'Not a task type',
				null
			);
			Assert.fail('Restricted picklist must reject an invalid value');
		} catch (AuraHandledException error) {
			Assert.isTrue(error.getMessage().startsWith(Constants.TODO_CREATE_ERROR));
		}
	}

	@IsTest
	static void unavailableAndWrongStateTasksCannotBeChanged() {
		Id contextId = accountId();
		Task openTask = [
			SELECT Id
			FROM Task
			WHERE Subject = 'Overdue call'
			LIMIT 1
		];
		Task closedTask = [
			SELECT Id
			FROM Task
			WHERE Subject = 'Closed task'
			LIMIT 1
		];
		Task unrelatedTask = [
			SELECT Id
			FROM Task
			WHERE Subject = 'Unrelated task'
			LIMIT 1
		];
		for (Id unavailableId : new List<Id>{ null, unrelatedTask.Id }) {
			try {
				AccountTodoController.completeTask(unavailableId, contextId);
				Assert.fail('A task outside this context must not be changed');
			} catch (AuraHandledException error) {
				Assert.isTrue(
					error.getMessage().contains(Constants.TODO_TASK_UNAVAILABLE)
				);
			}
		}
		try {
			AccountTodoController.completeTask(closedTask.Id, contextId);
			Assert.fail('Already closed must fail');
		} catch (AuraHandledException error) {
			Assert.isTrue(error.getMessage().contains(Constants.TODO_ALREADY_CLOSED));
		}
		try {
			AccountTodoController.scheduleNext(
				openTask.Id,
				contextId,
				'Too soon',
				null,
				null,
				null
			);
			Assert.fail('Follow-up requires a completed source task');
		} catch (AuraHandledException error) {
			Assert.isTrue(error.getMessage().contains(Constants.TODO_NOT_CLOSED));
		}
		try {
			AccountTodoController.scheduleNext(
				closedTask.Id,
				contextId,
				'Invalid owner',
				null,
				null,
				contextId
			);
			Assert.fail('An Account cannot own a task');
		} catch (AuraHandledException error) {
			Assert.isTrue(error.getMessage().contains(Constants.TODO_OWNER_INVALID));
		}
	}
}
