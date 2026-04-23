@RestResource(UrlMapping='/netsuite/product/*')
global with sharing class NetSuiteProductApi {

	global class ProductPayload {
		global List<ProductItem> items;
	}

	global class ProductItem {
		global String  netsuiteItemId;
		global Decimal committedQty;
	}

	@HttpPost
	global static void handlePost() {
		try {
			String requestBody = RestContext.request.requestBody.toString();
			System.debug(Constants.NETSUITE_PRODUCT_LOG_PAYLOAD + requestBody);

			ProductPayload payload = (ProductPayload) JSON.deserialize(
				requestBody, ProductPayload.class
			);

			if (isEmpty(payload)) {
				RestResponseUtils.sendBadRequest(Constants.NETSUITE_PRODUCT_MSG_EMPTY_PAYLOAD);
				return;
			}

			Map<String, Decimal> externalIdToCommitted = collectCommittedUpdates(payload.items);

			if (externalIdToCommitted.isEmpty()) {
				RestResponseUtils.sendOk(Constants.NETSUITE_PRODUCT_MSG_NO_VALID_ITEMS);
				return;
			}

			RestResponseUtils.sendOk(updateAndSummarize(externalIdToCommitted));

		} catch (Exception e) {
			System.debug(Constants.NETSUITE_PRODUCT_LOG_ERROR_PREFIX + e.getMessage() + '\n' + e.getStackTraceString());
			RestResponseUtils.sendInternalError(e);
		}
	}

	private static Boolean isEmpty(ProductPayload payload) {
		return payload == null || payload.items == null || payload.items.isEmpty();
	}

	private static Map<String, Decimal> collectCommittedUpdates(List<ProductItem> items) {
		Map<String, Decimal> result = new Map<String, Decimal>();
		for (ProductItem item : items) {
			if (String.isBlank(item.netsuiteItemId) || item.committedQty == null) {
				System.debug(Constants.NETSUITE_PRODUCT_LOG_SKIP_ITEM + JSON.serialize(item));
				continue;
			}
			result.put(item.netsuiteItemId, item.committedQty);
		}
		return result;
	}

	private static String updateAndSummarize(Map<String, Decimal> externalIdToCommitted) {
		Map<String, Product2> existingByExternalId = new Map<String, Product2>();
		for (Product2 p : Product2Selector.getProductsByExternalIds(externalIdToCommitted.keySet())) {
			existingByExternalId.put(p.External_Id__c, p);
		}

		List<Product2> toUpdate = new List<Product2>();
		List<String> missingIds = new List<String>();

		for (String externalId : externalIdToCommitted.keySet()) {
			Product2 existing = existingByExternalId.get(externalId);
			if (existing == null) {
				missingIds.add(externalId);
				continue;
			}
			toUpdate.add(new Product2(
				Id = existing.Id,
				Committed__c = externalIdToCommitted.get(externalId)
			));
		}

		Integer successCount = 0;
		List<String> errors = new List<String>();

		if (!toUpdate.isEmpty()) {
			Database.SaveResult[] results = Database.update(toUpdate, false);
			for (Integer i = 0; i < results.size(); i++) {
				if (results[i].isSuccess()) {
					successCount++;
				} else {
					String key = toUpdate[i].Id;
					for (Database.Error err : results[i].getErrors()) {
						errors.add(key + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
					}
				}
			}
		}

		logSummary(successCount, errors, missingIds);
		return buildMessage(successCount, errors, missingIds);
	}

	private static void logSummary(Integer successCount, List<String> errors, List<String> missingIds) {
		System.debug(
			Constants.NETSUITE_PRODUCT_LOG_UPDATE_SUMMARY + successCount
				+ ', Errors: ' + errors.size()
				+ ', Missing: ' + missingIds.size()
		);
		if (!errors.isEmpty()) {
			System.debug(Constants.NETSUITE_PRODUCT_LOG_UPDATE_ERRORS
				+ String.join(errors, Constants.HTTP_RESPONSE_ERROR_JOIN_SEPARATOR));
		}
		if (!missingIds.isEmpty()) {
			System.debug(Constants.NETSUITE_PRODUCT_LOG_MISSING
				+ String.join(missingIds, Constants.HTTP_RESPONSE_ERROR_JOIN_SEPARATOR));
		}
	}

	private static String buildMessage(Integer successCount, List<String> errors, List<String> missingIds) {
		String message = successCount + Constants.NETSUITE_PRODUCT_MSG_UPDATED_SUFFIX;
		if (!missingIds.isEmpty()) {
			message += ', ' + missingIds.size() + Constants.NETSUITE_PRODUCT_MSG_MISSING_SUFFIX
				+ ': ' + String.join(missingIds, Constants.HTTP_RESPONSE_ERROR_JOIN_SEPARATOR);
		}
		if (!errors.isEmpty()) {
			message += ', ' + errors.size() + Constants.NETSUITE_PRODUCT_MSG_FAILED_SUFFIX
				+ String.join(errors, Constants.HTTP_RESPONSE_ERROR_JOIN_SEPARATOR);
		}
		return message;
	}
}
