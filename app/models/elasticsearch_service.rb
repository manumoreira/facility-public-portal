class ElasticsearchService

  attr_reader :client

  def initialize(url, index_name, should_log: Rails.env.development?)
    @client     = Elasticsearch::Client.new url: url, log: should_log
    @index_name = index_name
  end

  def setup_index
    client.indices.create index: @index_name
  end

  def setup_mappings
    client.indices.put_mapping({
      index: @index_name,
      type: 'facility',
      body: {
        facility: {
          properties: {
            id: {
              type: 'long',
            },
            name: {
              type: 'string',
              index: 'analyzed',
              analyzer: "standard"
            },
            contact_phone: {type: 'string'},
            facility_type: {type: 'string', index: 'not_analyzed'},
            position: {type: 'geo_point'},
            last_updated: {
              type: 'date'
            }
          }
        }
      }
    })
  end

  def drop_index
    client.indices.delete index: @index_name
  end

  def index_facility(facility)
    index_document 'facility', facility
  end

  def index_facility_batch(facilities)
    index_batch 'facility', facilities
  end

  def index_facility_types(facility_types)
    index_batch 'facility_type', facility_types
  end

  def index_service(service)
    index_document 'service', service
  end

  def index_service_batch(services)
    index_batch 'service', services
  end

  def index_location(location)
    index_document 'location', location
  end

  def index_location_batch(locations)
    index_batch 'location', locations
  end

  def search_facilities(params)
    validate_search(params)

    size = params[:size].to_i
    size = 1000 if size == 0
    from = params[:from].to_i || 0

    search_body = {
      size: size,
      from: from,
      _source: [ "id", "name", "priority", "facility_type", "position", "adm" ],
      query: { bool: { must: [] } },
      sort: {}
    }

    if params[:q]
      search_body[:query][:bool][:must] << { match_phrase_prefix: { name: params[:q] } }
    end

    if params[:s]
      search_body[:query][:bool][:must] << { match: { service_ids: params[:s] } }
    end

    if params[:t]
      search_body[:query][:bool][:must] << { match: { facility_type_id: params[:t] } }
    end

    if params[:l]
      search_body[:query][:bool][:must] << { match: { adm_ids: params[:l] } }
    end

    if params[:lat] && params[:lng]
      search_body[:sort] = {
        _geo_distance: {
          position: {
            lat: params[:lat],
            lon: params[:lng]
          },
          order: "asc",
          unit:  "km",
          distance_type: "plane"
        }
      }
    end

    result = client.search({
      index: @index_name,
      type: 'facility',
      body: search_body
    })

    { items: result["hits"]["hits"].map { |r| api_latlng r["_source"] },
      from: from,
      size: size
    }.tap do |h|
      h[:next_from] = h[:from] + h[:size] if result["hits"]["hits"].count == h[:size]
    end
  end

  def get_facility_types
    result = client.search({index: @index_name, type: 'facility_type'})
    result["hits"]["hits"].map { |h| h["_source"] }
  end

  def get_facility(id)
    result = client.search({
      index: @index_name,
      type: 'facility',
      body: {
        size: 1,
        query: {
          match: {id: id}
        },
    }})

    api_latlng result["hits"]["hits"].first["_source"]
  end

  def suggest_services(query)
    result = client.search({
      index: @index_name,
      type: 'service',
      body: {
        query: {
          match_phrase_prefix: {
            name: query
          }
        },
    }})

    result["hits"]["hits"].map { |r| r["_source"] }
  end

  def suggest_facilities(params)
    # TODO
    #
    # For the moment we are just perforing a search restricted to 5 results.
    # Suggesting will probably involve using the suggest Elasticsearch API, which
    # trades scoring and analysis capabilities in favour of search speed.
    #
    # Also, we should consider returning a summary payload to reduce network traffic.
    search_facilities(params.merge({size: 5}))[:items]
  end

  def suggest_locations(query)
    result = client.search({
                             index: @index_name,
                             type: 'location',
                             body: {
                               size: 3,
                               query: {
                                 match_phrase_prefix: {
                                   name: query
                                 }
                               },
                             }})

    result["hits"]["hits"].map { |r| r["_source"] }
  end

  def self.instance
    @@instance ||= self.new(ENV['ELASTICSEARCH_URL'] || 'localhost',
                            ENV['ELASTICSEARCH_INDEX'] || 'fpp')
  end

  def self.instance=(instance)
    @@instance = instance
  end

  def self.client
    self.instance.client
  end

  private

  def validate_search(params)
    # TODO
  end

  def api_latlng(document)
    document["position"] = {
      "lat" => document["position"]["lat"].to_f,
      "lng" => document["position"]["lon"].to_f
    }
    document
  end

  def index_document(type, doc)
    client.index({
      index: @index_name,
      type: type,
      id: doc[:id],
      body: doc,
    })
  end

  def index_batch(type, docs)
    actions = docs.flat_map do |doc|
      [{ index: { _index: @index_name, _type: type, _id: doc[:id] } }, doc]
    end

    result = client.bulk body: actions
  end
end
