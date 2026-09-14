@microservice_types.keys.map do |m_id|
  @logger.debug "Microservice type: #{m_id}"
  [
    m_id,
    ComponentStatistics.new
  ]
end.to_h
