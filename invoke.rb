#!/usr/bin/env ruby
# By Erik Oliver
#
# License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)
# (C) 2016 Richardson Oliver Law Group

require './lib/FetchFreshbooks.rb'
require './lib/ParseFreshbooks.rb'
require './lib/StoreData.rb'

require 'awesome_print'

y = ParseFreshbooks.new()
dbhandle = StoreData.new()


ffb = FetchFreshbooks.new()

deleted = nil

# gets array of delete invoice ids if the database is not empty
if(dbhandle.return_date != '2000-01-01')
  deleted = y.get_deleted_invoices(dbhandle.return_date - 30)
end

results = y.get_all_invoices(dbhandle.return_date,dbhandle)

if (deleted != nil)
 dbhandle.drop_lines(deleted)
end

project_results = y.get_all_projects(dbhandle)

staff_results = y.get_staff_entries(dbhandle)

contractor_results = y.get_all_contractors(dbhandle)

time_entry_results = y.get_last_95_days_of_time_entries(dbhandle)
