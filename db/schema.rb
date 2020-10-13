# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2020_10_13_044558) do

  create_table "airports", force: :cascade do |t|
    t.string "name"
    t.string "identifier"
    t.float "lat"
    t.float "lng"
    t.string "overhead"
    t.string "upwind"
    t.string "crosswind"
    t.string "downwind"
    t.string "base"
    t.string "final"
    t.integer "approach_rwy"
    t.integer "departure_rwy"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "arrivals", force: :cascade do |t|
    t.integer "airport_id"
    t.string "tail_number"
    t.string "aircraft_type"
    t.datetime "arrived_at"
  end

  create_table "settings", force: :cascade do |t|
    t.integer "airport_id"
    t.boolean "use_1090dump"
    t.string "ip_1090dump"
    t.integer "port_1090dump"
    t.datetime "updated_at"
  end

end
