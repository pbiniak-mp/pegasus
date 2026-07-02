/**
 * Strategy contract for turning a source record + event type into the JSON body
 * sent to an external system. One implementation per integrated object.
 */
public interface IIntegrationPayloadBuilder {
	String buildPayload(SObject record, String eventType, Datetime eventTimestamp);
}
