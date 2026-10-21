public with sharing class AccountTodoController {
	@AuraEnabled(Cacheable=true)
	public static List<Task> getOpenTasks(Id recordId, Boolean myTasksOnly) {
		try {
			return AccountTodoService.getOpenTasks(recordId, myTasksOnly);
		} catch (Exception e) {
			throw handledError(Constants.TODO_LOAD_ERROR, e);
		}
	}

	@AuraEnabled
	public static void completeTask(Id taskId, Id recordId) {
		try {
			AccountTodoService.completeTask(taskId, recordId);
		} catch (Exception e) {
			throw handledError(Constants.TODO_COMPLETE_ERROR, e);
		}
	}

	@AuraEnabled
	public static Id createTask(
		Id recordId,
		String subject,
		String taskType,
		Date dueDate
	) {
		try {
			return AccountTodoService.createTask(
				recordId,
				subject,
				taskType,
				dueDate
			);
		} catch (Exception e) {
			throw handledError(Constants.TODO_CREATE_ERROR, e);
		}
	}

	@AuraEnabled
	public static Id scheduleNext(
		Id taskId,
		Id recordId,
		String subject,
		String taskType,
		Date dueDate,
		Id ownerId
	) {
		try {
			return AccountTodoService.scheduleNext(
				taskId,
				recordId,
				subject,
				taskType,
				dueDate,
				ownerId
			);
		} catch (Exception e) {
			throw handledError(Constants.TODO_CREATE_ERROR, e);
		}
	}

	@AuraEnabled(Cacheable=true)
	public static List<Map<String, String>> getTaskTypeOptions() {
		try {
			return AccountTodoService.getTaskTypeOptions();
		} catch (Exception e) {
			throw handledError(Constants.TODO_TYPE_ERROR, e);
		}
	}

	private static AuraHandledException handledError(
		String prefix,
		Exception cause
	) {
		String message = prefix + cause.getMessage();
		AuraHandledException error = new AuraHandledException(message);
		error.setMessage(message);
		return error;
	}
}
