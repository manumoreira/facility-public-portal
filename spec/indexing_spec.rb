require 'rails_helper'

include Helpers

RSpec.describe Indexing do
  describe "validations" do
    before (:each) { reset_index }

    let(:valid_dataset) do
      {facilities: [
         {
           id: "F1",
           name: "FOO",
           lat: 10.696144,
           lng: 38.370941,
           location_id: "L1",
           ownership: "Public",
           facility_type: "Health Center",
           contact_name: "",
           contact_email: nil,
           contact_phone: nil,
           last_update: nil
         }
       ],
       category_groups: [],
       categories: [],
       facility_categories: [],
       locations: [{id: "L1", name: "Ethiopia", parent_id: "-----------------"},],
       facility_types: []
      }
    end

    it "doesn't fail on empty dataseet" do
      dataset = {facilities: [],
                 category_groups: [],
                 categories: [],
                 facility_categories: [],
                 locations: [],
                 facility_types: []
                }
      expect{index_dataset(dataset)}.not_to raise_error
    end

    it "fails if a service name translation is missing" do
      locales = [:en, :am]
      dataset = {facilities: [
                         {
                           id: "F1",
                           name: "FOO",
                           lat: 10.696144,
                           lng: 38.370941,
                           location_id: "L1",
                           ownership: "Public",
                           facility_type: "Health Center",
                           contact_name: "",
                           contact_email: nil,
                           contact_phone: nil,
                           last_update: nil
                         }
                       ],
                       category_groups: [
                        {
                          id: 'services',
                          'name:en': 'Services',
                          'name:am': 'አገልግሎቶች'
                        }
                       ],
                       categories: [
                         {
                           id: "S1",
                           category_group_id: 'services',
                           'name:en': 'Vaccines'
                           # name:am is missing
                         }
                       ],
                       facility_categories: [{facility_id: "F1", category_id: "S1"}],
                       locations: [{id: "L1", name: "Ethiopia", parent_id: "-----------------"},],
                       facility_types: []
                      }

      expect { index_dataset(dataset, locales) }.to raise_error("Missing translation")
    end

    it "skips facilities without a name" do
      index_dataset({facilities: [
                       {
                         id: "INVALID",
                         name: nil,
                         lat: 10.696144,
                         lng: 38.370941,
                         location_id: "L1",
                         facility_type: "Health Center",
                         contact_name: "",
                         contact_email: nil,
                         contact_phone: nil,
                         last_update: nil
                       }
                     ],
                     category_groups: [],
                     categories: [],
                     facility_categories: [],
                     locations: [{id: "L1", name: "Ethiopia", parent_id: "-----------------"},],
                     facility_types: []
                    })

      expect(all_facilities).to be_empty
    end

    it "skips facilities without facility_type" do
      index_dataset({facilities: [
                       {
                         id: "INVALID",
                         name: "FOO",
                         lat: 10.696144,
                         lng: 38.370941,
                         location_id: "L1",
                         facility_type: nil,
                         contact_name: "",
                         contact_email: nil,
                         contact_phone: nil,
                         last_update: nil
                       }
                     ],
                     category_groups: [],
                     categories: [],
                     facility_categories: [],
                     locations: [{id: "L1", name: "Ethiopia", parent_id: "-----------------"},],
                     facility_types: []
                    })

      expect(all_facilities).to be_empty
    end

    it "skips facilities without lat/lng" do
      index_dataset({facilities: [
                       {
                         id: "INVALID1",
                         name: "FOO",
                         lat: nil,
                         lng: 38.370941,
                         location_id: "L1",
                         facility_type: "Health Center",
                         contact_name: "",
                         contact_email: nil,
                         contact_phone: nil,
                         last_update: nil
                       },
                       {
                         id: "INVALID2",
                         name: "FOO",
                         lat: 10.696144,
                         lng: nil,
                         location_id: "L1",
                         facility_type: "Health Center",
                         contact_name: "",
                         contact_email: nil,
                         contact_phone: nil,
                         last_update: nil
                       }
                     ],
                     category_groups: [],
                     categories: [],
                     facility_categories: [],
                     locations: [{id: "L1", name: "Ethiopia", parent_id: "-----------------"},],
                     facility_types: []
                    })

      expect(all_facilities).to be_empty
    end

    it "indexes facilities without ownership" do
      index_dataset({facilities: [
         {
           id: "F1",
           name: "FOO",
           lat: 10.696144,
           lng: 38.370941,
           location_id: "L1",
           facility_type: "Health Center",
           contact_name: "",
           contact_email: nil,
           contact_phone: nil,
           last_update: nil
         }
       ],
       category_groups: [],
       categories: [],
       facility_categories: [],
       locations: [{id: "L1", name: "Ethiopia", parent_id: "-----------------"},],
       facility_types: []
      })

      result = all_facilities
      expect(result.size).to eq(1)
      expect(result[0]["ownership_id"]).to eq(nil)
    end

    it "indexes a valid facility" do
      index_dataset(valid_dataset)

      expect(all_facilities.size).to eq(1)

      all_facilities[0].tap do |f|
        expect(f["ownership"]).to eq("Public")
      end
    end

    # This is to prevent Elm from hanging when the facility decoder fails downstream
    # Looks like real world files come with a lot of "numeric gibberish" so it'd be
    # too cumbersome for users if we asked them to make sure those always come
    # enclosed in quotes. We just do it at the moment of indexing and that's it.
    it "coerces some fields to string when indexiong" do
      string_coerced_fields = [:name, :address, :contact_name, :contact_phone, :contact_email]

      string_coerced_fields.each do |field|
        valid_dataset[:facilities][0][field] = 0
      end

      index_dataset(valid_dataset)

      expect(all_facilities.size).to eq(1)

      all_facilities[0].tap do |f|
        string_coerced_fields.each do |field|
          expect(f[field.to_s]).to eq("0"), "expected \"0\", got #{f[field.to_s]} from field \"#{field.to_s}\""
        end
      end
    end


    describe "facility priority" do
      context "priority is not explicit in the dataset" do
        it "assigns minimum value" do
          index_dataset(valid_dataset)

          facility = all_facilities[0]
          expect(facility["priority"]).to eq(0)
        end
      end

      context "priority is explicit in the dataset" do
        it "assigns priority based no the facility's type" do
          index_dataset(valid_dataset.tap do |ds|
                          ds[:facility_types] = [ { name: "Health Center", priority: 3 } ]
                        end)

          facility = all_facilities[0]
          expect(facility["priority"]).to eq(3)
        end
      end
    end

    describe "facility types" do
      it "indexes facility types in the facility_types table" do
        dataset = {facilities: [],
                   category_groups: [],
                   categories: [],
                   facility_categories: [],
                   locations: [{id: "L1", name: "Ethiopia", parent_id: "-----------------"},],
                   facility_types: [
                     { name: "Health Center", priority: 1 },
                     { name: "Hospital", priority: 2 }
                   ]
                  }
        index_dataset(dataset)

        expect(all_facility_types.size).to eq(2)
        expect(all_facility_types.map { |t| t["id"] }.sort).to eq([1,2])
      end

      it "indexes facility types not present in facility_types table" do
        dataset = {facilities: [
                     {id: "F1", name: "FOO", lat: 10.696144, lng: 38.370941, location_id: "L1", facility_type: "Hospital", ownership: "Public"}
                   ],
                   category_groups: [],
                   categories: [],
                   facility_categories: [],
                   locations: [{id: "L1", name: "Ethiopia", parent_id: "-----------------"},],
                   facility_types: []
                  }
        index_dataset(dataset)

        types = all_facility_types
        expect(types.size).to eq(1)

        type = types[0]
        expect(type["name"]).to eq("Hospital")
        expect(type["id"]).to eq(1)
      end
    end

    describe "ownerships" do
      it "indexes distinct ownership types" do
        dataset = {
          facilities: [
            {id: "F1", name: "FOO", lat: 10.696144, lng: 38.370941, location_id: "L1", ownership: "Public", facility_type: "Health Center"},
            {id: "F2", name: "BAR", lat: 10.696144, lng: 38.370941, location_id: "L1", ownership: "Private", facility_type: "Health Center"}
          ],
          category_groups: [],
          categories: [],
          facility_categories: [],
          locations: [{id: "L1", name: "Ethiopia", parent_id: "-----------------"},],
          facility_types: []
        }

        index_dataset(dataset)

        expect(all_ownerships.size).to eq(2)
        expect(all_ownerships.sort { |o| o["id"] }).to eq([{ "id" => 1, "name" => "Public" }, { "id" => 2, "name" => "Private" }])
      end
    end
  end

  def all_facilities
    result = elasticsearch_service.client.search index: TESTING_INDEX, type: 'facility'
    result["hits"]["hits"].map { |hit| hit["_source"] }
  end

  def all_ownerships
    result = elasticsearch_service.client.search index: TESTING_INDEX, type: 'ownership'
    result["hits"]["hits"].map { |hit| hit["_source"] }
  end

  def all_facility_types
    result = elasticsearch_service.client.search index: TESTING_INDEX, type: 'facility_type'
    result["hits"]["hits"].map { |hit| hit["_source"] }
  end
end
