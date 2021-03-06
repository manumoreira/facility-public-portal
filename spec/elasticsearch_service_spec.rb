require 'rails_helper'

include Helpers

RSpec.describe ElasticsearchService do

  before(:context) do
    reset_index

    index_dataset({facilities: [
                     {
                        id: "F1",
                        name: "1st Wetanibo Balchi",
                        lat: 8.958315,
                        lng: 38.761659,
                        location_id: "L3",
                        facility_type: "Health Center",
                        ownership: "Government/Public",
                        contact_name: "",
                        contact_email: nil,
                        contact_phone: nil,
                        last_update: nil
                     },
                     {
                       id: "F2",
                       name: "Abaferet Hospital",
                       lat: 10.696144,
                       lng: 38.370941,
                       location_id: "L4",
                       facility_type: "Primary Hospital",
                       ownership: "Other governmental (military, prison, police)",
                       contact_name: "",
                       contact_email: nil,
                       contact_phone: nil,
                       last_update: nil
                     },
                     {
                        id: "F3",
                        name: "Efoyta Health Center",
                        lat: 11.361093,
                        lng: 37.917412,
                        location_id: "L2",
                        facility_type: "Health Center",
                        ownership: "Government/Public",
                        contact_name: "",
                        contact_email: nil,
                        contact_phone: nil,
                        last_update: nil
                     }
                   ],

                   category_groups: [
                     { id: 'services', 'name:en': 'Services' }
                   ],

                   categories: [
                     { id: "S1", category_group_id: 'services', "name:en": "service1" },
                     { id: "S2", category_group_id: 'services', "name:en": "service2" },
                     { id: "S3", category_group_id: 'services', "name:en": "service3" }
                   ],

                   facility_categories: [
                     {facility_id: "F1", category_id: "S1"},
                     {facility_id: "F1", category_id: "S2"},

                     {facility_id: "F2", category_id: "S2"},
                     {facility_id: "F2", category_id: "S3"}
                   ],

                   facility_types: [
                     { name: "Health Center", priority: 1 },
                     { name: "Primary Hospital", priority: 2 },
                   ],

                   locations: [
                     {id: "L1", name: "Ethiopia", parent_id: "-----------------"},
                     {id: "L2", name: "Snnp Region", parent_id: "L1"},
                     {id: "L3", name: "Gurage Zone", parent_id: "L2"},
                     {id: "L4", name: "Hadiya Zone", parent_id: "L2"}
                   ]})
  end

  describe "search" do
    describe "by name" do
      it "searches by word prefix" do
        search_assert({ q: "Wet" }, expected_names: ["1st Wetanibo Balchi"])
      end

      it "searches by inner words" do
        search_assert({ q: "Bal" }, expected_names: ["1st Wetanibo Balchi"])
      end
    end

    describe "by category" do
      it "works!" do
        search_assert({ category: 1 }, expected_names: ["1st Wetanibo Balchi"])
        search_assert({ category: 2 }, expected_names: ["1st Wetanibo Balchi", "Abaferet Hospital"])
        search_assert({ category: 3 }, expected_names: ["Abaferet Hospital"])
      end
    end

    describe "by administrative location" do
      it "works!" do
        search_assert({ location: 1 }, expected_names: ["1st Wetanibo Balchi","Abaferet Hospital","Efoyta Health Center"])
        search_assert({ location: 2 }, expected_names: ["1st Wetanibo Balchi","Abaferet Hospital","Efoyta Health Center"])
        search_assert({ location: 3 }, expected_names: "1st Wetanibo Balchi")
        search_assert({ location: 4 }, expected_names: "Abaferet Hospital")
      end
    end

    describe "by facility type" do
      it "works!" do
        search_assert({ type: 1 }, expected_names: ["1st Wetanibo Balchi", "Efoyta Health Center"])
        search_assert({ type: 2 }, expected_names: ["Abaferet Hospital"])
      end
    end

    describe "by ownership" do
      it "works!" do
        search_assert({ ownership: 1 }, expected_names: ["1st Wetanibo Balchi", "Efoyta Health Center"])
        search_assert({ ownership: 2 }, expected_names: ["Abaferet Hospital"])
      end
    end

    describe "sorting" do
      it "sorts by proximity to user location by default" do
        search_assert(
          { lat: 8.959169, lng: 38.827452 },
          expected_names: ["1st Wetanibo Balchi", "Abaferet Hospital", "Efoyta Health Center"],
          order_matters: true
        )

        search_assert(
          { lat: 10.622245, lng: 38.646663 },
          expected_names: ["Abaferet Hospital", "Efoyta Health Center" , "1st Wetanibo Balchi"],
          order_matters: true
        )
      end

      it "supports sorting by facility type" do
        names = search_names({ lat: 8.959169, lng: 38.827452, sort: :type })
        expect(names.size).to eq(3)
        expect(names.first).to eq("Abaferet Hospital")
      end

      it "supports sorting by name" do
        search_assert(
          { lat: 10.622245, lng: 38.646663, sort: :name },
          expected_names: ["1st Wetanibo Balchi", "Abaferet Hospital", "Efoyta Health Center"],
          order_matters: true
        )
      end
    end
  end

  describe "suggestions" do
    describe "facilities" do
      # TODO: same as searchiing for the moment...
    end

    describe "categories" do
      it "works" do
        [1,2,3].each do |i|
          results = elasticsearch_service.suggest_categories("service#{i}")
          expect(results.map { |s| s['id'] }).to eq([i])
        end
      end
    end

    describe "locations" do
      it "works" do
        results = elasticsearch_service.suggest_locations("Hadi")
        expect(results.size).to eq(1)

        results[0].tap do |r|
          expect(r["source_id"]).to eq("L4")
          expect(r["name"]).to eq("Hadiya Zone")
          expect(r["facility_count"]).to eq(1)
          expect(r["parent_name"]).to eq("Snnp Region")
        end
      end
    end
  end

  it "provides all distinct ownership kinds" do
    expect(elasticsearch_service.get_ownerships.size).to eq(2)
  end

  def search_names(params)
    results = elasticsearch_service.search_facilities(params)[:items]
    results.map { |r| r['name'] }
  end

  def search_assert(params, expected_names:, order_matters: false)
    actual_names = search_names(params)
    if order_matters
      expect(actual_names).to eq(expected_names)
    else
      expect(actual_names).to match_array(expected_names)
    end
  end
end
