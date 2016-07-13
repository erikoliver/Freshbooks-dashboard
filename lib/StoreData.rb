#!/usr/bin/ruby
# By Erik Oliver
#
# License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)
# (C) 2016 Richardson Oliver Law Group
require 'rubygems'


# note getting mysql for Mac OS X Yosemite
# 	bash <(curl -Ls http://git.io/eUx7rg)
# Fix the libraries
# 	sudo ln -s /usr/local/mysql/lib/libmysqlclient.18.dylib /usr/lib/libmysqlclient.18.dylib
# install the gem
# 	sudo gem install mysql2
# Documentation - http://www.rubydoc.info/gems/mysql2/0.3.11/frames
require 'mysql2'

DBCHOICE = 'mysql' #<-- NOTE: change server here

class Mysql2::Client
	def execute(block)
		query(block)
	end
end

class Mysql2::Result
	def length
		count()
	end
end

class StoreData

	# Open a handle to the database on New
	#NOTE: add server here
	def initialize(dbfilename = nil)
		@database = nil
		if (DBCHOICE == 'mysql') then
			@database = Mysql2::Client.new(
				:host => 'mysql.yourdomain.com',
				:username => 'yourusername',
				:password => 'yourpassword',
				:database => 'yourdb'
			)
			create_tables_mysql()
		elsif(DBCHOICE == 'mysqltest') then
			@database = Mysql2::Client.new(
				:host => 'localhost',
				:username => 'yourusername',
				:password => 'yourpassword',
				:database => 'yourdb'
			)
				create_tables_mysql()
		else
			raise "unknown DBCHOICE='#{DBCHOICE}'"
		end # if DBCHOICE
	end

	# close the database
	def closedb()
		@database.close()
	end

	# Call this as part of initialize to ensure all tables exist
	#create tables's and views in mysql database
	def create_tables_mysql()

		dbrows = @database.query <<-SQL
		CREATE TABLE IF NOT EXISTS invoices (
			organization VARCHAR(255),
			updated DATE,
			amount FLOAT,
			amount_outstanding FLOAT,
			discount FLOAT,
			invoice_id VARCHAR(255),
			number VARCHAR(255) UNIQUE PRIMARY KEY,
			matter VARCHAR(255),
			status VARCHAR(255),
			date DATE
			);
			SQL

			dbrows = @database.query <<-SQL
			CREATE TABLE IF NOT EXISTS invoice_lines (
				line_id INTEGER,
				_order INTEGER,
				number VARCHAR(255),
				invoice_id VARCHAR(255),
				description TEXT,
				amount FLOAT,
				first_expense_id INTEGER,
			  first_time_entry_id TEXT,
				line_item_date VARCHAR(255),
				person VARCHAR(512),
				name VARCHAR(255),
				unit_cost FLOAT,
				quantity FLOAT,
				type VARCHAR(255),
				matter VARCHAR(255),
				updated DATE
				);
				SQL
		## Add code here if you end up making additional tables

		dbrows = @database.query <<-SQL
		CREATE TABLE IF NOT EXISTS projects (
			matter VARCHAR(255) UNIQUE,
			name VARCHAR(255),
			project_id VARCHAR(255),
			hour_budget FLOAT
			);
			SQL
		dbrows = @database.query('DELETE FROM projects;')

		dbrows = @database.query <<-SQL
		CREATE TABLE IF NOT EXISTS time_entries (
			time_entry_id INTEGER UNIQUE,
			staff_id INTEGER,
			project_id VARCHAR(255),
			task_id INTEGER,
			hours FLOAT,
			date DATE,
			notes TEXT,
			billed INTEGER
		);
		SQL
		dbrows = @database.query('DELETE FROM time_entries;')

		dbrows = @database.query <<-SQL
		CREATE TABLE IF NOT EXISTS staff (
			person VARCHAR(512),
			first_name VARCHAR(255),
			last_name VARCHAR(255),
			staff_id INTEGER,
			rate FLOAT
		);
		SQL
		dbrows = @database.query('DELETE FROM staff;')

		dbrows = @database.query <<-SQL
		CREATE TABLE IF NOT EXISTS contractor (
			name VARCHAR(255),
			contractor_id INTEGER,
			rate FLOAT
		);
		SQL
		dbrows = @database.query('DELETE FROM contractor;')

		dbrows = @database.query <<-SQL
			-- estimates from Contractors
			CREATE OR REPLACE VIEW unbilled_contractor_time AS
				SELECT projects.matter, contractor.name as person, SUM(time_entries.hours * contractor.rate) as estimated
				FROM time_entries
				INNER JOIN  projects ON projects.project_id = time_entries.project_id
				INNER JOIN  contractor ON contractor.contractor_id = time_entries.staff_id
				WHERE projects.matter <> '' AND time_entries.billed = 0
				GROUP BY projects.matter, person
			;
			SQL

			#UNBILLED STAFF TIME view
		dbrows = @database.query <<-SQL
		-- Estimates from Staff
			CREATE OR REPLACE VIEW unbilled_staff_time AS
					SELECT projects.matter, staff.person, SUM(time_entries.hours * staff.rate) as estimated
					FROM time_entries
					INNER JOIN  projects ON projects.project_id = time_entries.project_id
					INNER JOIN  staff ON staff.staff_id = time_entries.staff_id
					WHERE projects.matter <> '' AND time_entries.billed = 0
					GROUP BY projects.matter, staff.person
					ORDER BY projects.matter, staff.person
					;

			SQL

		#UNBILLED ALL TIME TEMP view
		dbrows = @database.query <<-SQL
			CREATE OR REPLACE VIEW unbilled_all_time_temp AS
					SELECT * FROM unbilled_staff_time
					UNION
					SELECT * FROM unbilled_contractor_time;
			SQL

		#UNBILLED ALL TIME view
		dbrows = @database.query <<-SQL
			-- All unbilled time
				CREATE OR REPLACE VIEW unbilled_all_time AS
					SELECT *
					FROM unbilled_all_time_temp
					GROUP BY unbilled_all_time_temp.matter, unbilled_all_time_temp.person
				;
				SQL

		#mysql version
		#INVOICES GROUP view
		dbrows = @database.query <<-SQL
			CREATE OR REPLACE VIEW invoices_grouped AS
					SELECT
							invoices.organization
						, invoices.matter
						, SUM((CASE WHEN status <> 'draft' THEN invoices.amount ELSE 0 END)) AS lifetime_billed
						, SUM((CASE WHEN YEAR(invoices.date) = YEAR(NOW()) THEN
							(CASE WHEN status <> 'draft' THEN invoices.amount ELSE 0 END)
							ELSE 0 END)) as ytd_billed
						, SUM((CASE WHEN status = 'draft' THEN invoices.amount ELSE 0 END)) as draft_invoices
						, SUM((CASE WHEN status <> 'draft' THEN invoices.amount_outstanding ELSE 0 END)) as outstanding
					FROM invoices
					GROUP BY invoices.organization, invoices.matter;
			SQL

		#ORGNAMES view
		dbrows = @database.query <<-SQL
			CREATE OR REPLACE VIEW orgnames AS
				SELECT DISTINCT invoices_grouped.organization, unbilled_all_time.matter
				FROM unbilled_all_time
				LEFT OUTER JOIN invoices_grouped ON SUBSTR(invoices_grouped.matter,1,4) = SUBSTR(unbilled_all_time.matter,1,4);
			SQL

		dbrows = @database.query <<-SQL
			-- Build a deconstructed invoice from the line items
			CREATE OR REPLACE VIEW apportioned_invoices AS
						SELECT
								invoices.organization
							, invoices.updated
							, (invoice_lines.amount - (invoice_lines.amount * invoices.discount/100)) as amount
							, (invoices.amount_outstanding/invoices.amount) * (invoice_lines.amount - (invoice_lines.amount * invoices.discount/100)) as amount_outstanding
							, invoices.discount
							, invoices.invoice_id
							, invoices.number
							, invoices.matter
							, invoices.status
							, invoices.date
							, (CASE WHEN invoice_lines.person = '' OR invoice_lines.person IS NULL THEN 'no name found' ELSE invoice_lines.person END) as person
							, invoice_lines.type
						FROM invoice_lines
						LEFT OUTER JOIN invoices ON invoices.invoice_id = invoice_lines.invoice_id
						;
			SQL

		dbrows = @database.query <<-SQL
			CREATE OR REPLACE VIEW apportioned_invoices_grouped AS
					SELECT
							apportioned_invoices.organization
						, apportioned_invoices.matter
						, apportioned_invoices.person
						, SUM((CASE WHEN apportioned_invoices.status <> 'draft' THEN apportioned_invoices.amount ELSE 0 END)) AS lifetime_billed
						, SUM((CASE WHEN YEAR(apportioned_invoices.date) = YEAR(NOW()) THEN
							(CASE WHEN apportioned_invoices.status <> 'draft' THEN apportioned_invoices.amount ELSE 0 END)
							ELSE 0 END)) as ytd_billed
						, SUM((CASE WHEN apportioned_invoices.status = 'draft' THEN apportioned_invoices.amount ELSE 0 END)) as draft_invoices
						, SUM(unbilled_all_time.estimated) AS estimated
						, SUM((CASE WHEN apportioned_invoices.status <> 'draft' THEN apportioned_invoices.amount_outstanding ELSE 0 END)) as outstanding
					FROM apportioned_invoices
					LEFT OUTER JOIN unbilled_all_time ON apportioned_invoices.matter = unbilled_all_time.matter AND apportioned_invoices.person = unbilled_all_time.person
					GROUP BY apportioned_invoices.organization, apportioned_invoices.matter, apportioned_invoices.person;
					;
				SQL

		#UNBILLED ALL TIME WITH ORGS view
		dbrows = @database.query <<-SQL
			-- need to fix up matters
			CREATE OR REPLACE VIEW unbilled_all_time_with_orgs AS
					SELECT (CASE WHEN orgnames.organization <> '' THEN orgnames.organization ELSE 'unknown organization' END) as organization, unbilled_all_time.person, unbilled_all_time.matter, unbilled_all_time.estimated
					FROM unbilled_all_time
					LEFT OUTER JOIN orgnames ON orgnames.matter = unbilled_all_time.matter
				;
			SQL

		dbrows = @database.query <<-SQL
			CREATE OR REPLACE VIEW dashboard_detailed AS
					SELECT
							apportioned_invoices_grouped.organization
						, apportioned_invoices_grouped.matter
						, apportioned_invoices_grouped.person
						, apportioned_invoices_grouped.lifetime_billed
						, apportioned_invoices_grouped.ytd_billed
						, apportioned_invoices_grouped.outstanding
						, apportioned_invoices_grouped.draft_invoices
						, (CASE WHEN unbilled_all_time_with_orgs.estimated IS NULL THEN 0 ELSE unbilled_all_time_with_orgs.estimated END) as estimated
						, (apportioned_invoices_grouped.lifetime_billed + apportioned_invoices_grouped.draft_invoices + (CASE WHEN unbilled_all_time_with_orgs.estimated IS NULL THEN 0 ELSE unbilled_all_time_with_orgs.estimated END)) as all_spend
					FROM apportioned_invoices_grouped
					LEFT OUTER JOIN unbilled_all_time_with_orgs ON unbilled_all_time_with_orgs.matter = apportioned_invoices_grouped.matter AND unbilled_all_time_with_orgs.person = apportioned_invoices_grouped.person
					UNION
					-- Find the other half of the FULL OUTER JOIN
					SELECT
							unbilled_all_time_with_orgs.organization
						, unbilled_all_time_with_orgs.matter
						, unbilled_all_time_with_orgs.person
						, 0 as lifetime_billed
						, 0 as ytd_billed
						, 0 as outstanding
						, 0 as draft_invoices
						, unbilled_all_time_with_orgs.estimated
						, unbilled_all_time_with_orgs.estimated as all_spend
					FROM unbilled_all_time_with_orgs
					LEFT OUTER JOIN apportioned_invoices_grouped ON apportioned_invoices_grouped.matter = unbilled_all_time_with_orgs.matter AND apportioned_invoices_grouped.person = unbilled_all_time_with_orgs.person
					WHERE apportioned_invoices_grouped.matter IS NULL;
				;
			SQL



			#DASHBOARD view
			dbrows = @database.query <<-SQL
				CREATE OR REPLACE VIEW dashboard AS
					SELECT
					  	organization
					  , matter
					  , SUM(lifetime_billed) as lifetime_billed
					  , SUM(ytd_billed) as ytd_billed
					  , SUM(outstanding) as outstanding
					  , SUM(draft_invoices) as draft_invoices
					  , SUM(estimated) as estimated
					  , SUM(all_spend) as all_spend
					FROM dashboard_detailed
					GROUP BY matter
				;
			SQL
	end

	# Test for existence of record with the unique parameter 'number'
	#INPUTS: table field 'number'
	#OUTPUTS: true if exists & false if not exist
	def invoice_recordexists(h)
		rows = @database.execute("SELECT * FROM invoices WHERE number='#{h['number']}';")
		line_rows = @database.execute("SELECT * FROM invoice_lines WHERE number='#{h['number']}';")
		if(rows.length > 0 && line_rows.length > 0) then
			return true
		else
			return false
		end
	end

	# If the table invoices has data update fields to 'number'
	# INPUTS: takes a hash of parsed fields
	# OUTPUTS: all data is stored to the freshbooks sqlite or mysql database
	def invoice_update(h)
		rows = @database.execute <<-SQL
			UPDATE invoices
			SET
					organization = '#{h['organization']}'
				, updated = '#{h['updated']}'
				, amount = '#{h['amount']}'
				, amount_outstanding = '#{h['amount_outstanding']}'
				, discount = '#{h['discount']}'
				, invoice_id = '#{h['invoice_id']}'
				, matter = '#{h['matter']}'
				, date = '#{h['date']}'
				, status = '#{h['status']}'
			WHERE number = '#{h['number']}';
			SQL
	end

	# If the table invoice_lines has data update fields to 'number' and 'line_id'
	# INPUTS: takes a hash of parsed fields
	# OUTPUTS: all data is stored to the freshbooks sqlite or mysql database
	def line_item_update(h)
		rows = @database.execute <<-SQL
		UPDATE invoice_lines
		SET
				_order = '#{h['order']}'
			, invoice_id = '#{h['invoice_id']}'
			, name = '#{h['name']}'
			, matter = '#{h['matter']}'
			, description = '#{h['description']}'
			, amount = '#{h['amount']}'
			, first_expense_id = '#{h['first_expense_id']}'
			, first_time_entry_id = '#{h['first_time_entry_id']}'
			, line_item_date = '#{h['line_item_date']}'
			, person = '#{h['person']}'
			, unit_cost = '#{h['unit_cost']}'
			, quantity = '#{h['quantity']}'
			, type = '#{h['type']}'
			, updated = '#{h['updated']}'
		WHERE (number = '#{h['number']}' AND line_id = '#{h['line_id']}');
		SQL
	end

	#if the table doesn't have records insert all record
	#INPUTS: takes a hash of parsed fields
	#OUTPUTS: all data is stored to the freshbooks sql database
	def invoice_insert(h)
		rows = @database.execute <<-SQL
		INSERT INTO invoices
			( number
			, organization
			, updated
		  , amount
			, amount_outstanding
			, discount
		 	, invoice_id
			, matter
			, date
			, status)
		VALUES
		('#{h['number']}'
		, '#{h['organization']}'
		, '#{h['updated']}'
		, '#{h['amount']}'
		, '#{h['amount_outstanding']}'
		, '#{h['discount']}'
		, '#{h['invoice_id']}'
		, '#{h['matter']}'
		, '#{h['date']}'
		, '#{h['status']}'
	 	 )
		 SQL
	end

	#if the table invoice_lines record doesn't exist insert all record
	#INPUTS: takes a hash of parsed fields
	#OUTPUTS: all data is stored to the freshbooks sql database
	def line_item_insert(h)
		rows = @database.execute  <<-SQL
		INSERT INTO invoice_lines
				(number
				, invoice_id
				, line_id
				, _order
				, description
				, amount
				, first_expense_id
		  	, first_time_entry_id
				, line_item_date
				, person
				, name
				, matter
				, unit_cost
				, quantity
				, type
				, updated
				)
		VALUES
			 ('#{h['number']}'
			 , '#{h['invoice_id']}'
			 , '#{h['line_id']}'
			 , '#{h['order']}'
			 , '#{h['description']}'
			 , '#{h['amount']}'
			 , '#{h['first_expense_id']}'
			 , '#{h['first_time_entry_id']}'
			 , '#{h['line_item_date']}'
		   , '#{h['person']}'
			 , '#{h['name']}'
			 , '#{h['matter']}'
			 , '#{h['unit_cost']}'
			 , '#{h['quantity']}'
			 , '#{h['type']}'
			 , '#{h['updated']}'
			 )
		SQL
	end

	#find max update from invoices table
	#selects database base on DBCHOICE
	#OUTPUTS: returns 'maxmodified'
	def last_modified_date()
		max_update = @database.execute("SELECT MAX(updated) as maxmodified FROM invoices;")
		if (DBCHOICE == 'sqlite3') then
			return max_update[0][0]
		elsif (DBCHOICE == 'mysqltest' || DBCHOICE == 'mysql') then
			# structure is hash of hashes, look for the maxmodified key in 1st record and return
			max_update.each do |row|
				return row['maxmodified']
			end # max_update.each
		end
	end

	#find max update from invoice_lines table
	#selects database base on DBCHOICE
	#OUTPUTS: returns 'maxmodified'
	def last_line_modified_date()
		max_update = @database.execute("SELECT MAX(updated) as maxmodified FROM invoice_lines;")
		if (DBCHOICE == 'sqlite3') then
			return max_update[0][0]
		elsif (DBCHOICE == 'mysqltest' || DBCHOICE == 'mysql') then
			# structure is hash of hashes, look for the maxmodified key in 1st record and return
			max_update.each do |row|
				return row['maxmodified']
		end # max_update.each
	end
end

	#since invoice_lines and invoices tables both use the same XML this returns the smaller of the two 'maxmodified'
	#this way they don't fall out of sync
	#OUTPUTS: last_line_modified_date || last_modified_date || '2000-01-01'
	def return_date
		if(last_line_modified_date && last_modified_date != nil)
			if(last_line_modified_date <= last_modified_date)
				return last_line_modified_date()
			else
				return last_modified_date()
			end
		else
			return '2000-01-01'
		end
	end

	#function is called in invoke.rb and drops all lines WHERE updated >= date
	#INPUTS: date = (return_date-30)
	#OUTPUTS: drops lines in invoice_lines
	def drop_lines(array)
		array.each do |el|
			dbrows = @database.query <<-SQL
				DELETE FROM invoice_lines WHERE invoice_id = '#{el}';
			SQL
		end
	end

	# Goal: Receive a hash with invoices table fields and store in database or update existing row
	#INPUTS: takes a hash of parsed fields
	#OUTPUTS: data goes to the database
	def invoice_updateinsert(recordhash)
		if(invoice_recordexists(recordhash)) then
			invoice_update(recordhash)
		else
			invoice_insert(recordhash)
		end
	end

	# Goal: Receive a hash with invoice_lines table fields and store in database or update existing row
	#INPUTS: takes a hash of parsed fields
	#OUTPUTS: data goes to the database
	def invoice_line_updateinsert(recordhash)
		if(invoice_recordexists(recordhash)) then
			line_item_update(recordhash)
		else
			line_item_insert(recordhash)
		end
	end



	#inserts all projects into to the database
	#INPUTS: takes a hash of parsed fields
	#OUTPUTS: data goes to the database
	def project_insert(h)
		if(h['matter'] == '' || h['matter'] == nil) then
			command = <<-SQL
			INSERT INTO projects
				( matter
				, project_id
				, name
				, hour_budget
				)
			VALUES
				(NULL
				, '#{h['project_id']}'
				, '#{h['name']}'
				, '#{h['hour_budget']}'
				)
			SQL
		else
 			command = <<-SQL
			INSERT INTO projects
				( matter
				, project_id
				, name
				, hour_budget
				)
			VALUES
				('#{h['matter']}'
				, '#{h['project_id']}'
				, '#{h['name']}'
			 	, '#{h['hour_budget']}'
				)
			SQL
		end #if
		rows = @database.execute(command)
	end

	#inserts all time_entries into to the database
	#INPUTS: takes a hash of parsed fields
	#OUTPUTS: data goes to the database
	def time_entry_insert(h)
 		rows = @database.execute <<-SQL
			INSERT INTO time_entries
				(time_entry_id
				, staff_id
				, project_id
				, task_id
				, hours
				, date
				, notes
				, billed
				)
			VALUES
				('#{h['time_entry_id']}'
				, '#{h['staff_id']}'
				, '#{h['project_id']}'
				, '#{h['task_id']}'
				, '#{h['hours']}'
				, '#{h['date']}'
				, '#{h['notes']}'
				, '#{h['billed']}'
				)
		SQL
	end

	#inserts all projects into to the database
	#INPUTS: takes a hash of parsed fields
	#OUTPUTS: data goes to the database
	def staff_insert(h)
 		rows = @database.execute <<-SQL
			INSERT INTO staff
				( person
				, first_name
				, last_name
				, staff_id
				, rate
				)
			VALUES
				('#{h['person']}'
				, '#{h['first_name']}'
				, '#{h['last_name']}'
				, '#{h['staff_id']}'
				, '#{h['rate']}'
				)
		SQL
	end

	#inserts all contactors into to the database
	#INPUTS: takes a hash of parsed fields
	#OUTPUTS: data goes to the database
	def contractor_insert(h)
 		rows = @database.execute <<-SQL
			INSERT INTO contractor
				(name
				, contractor_id
				, rate
				)
			VALUES
				('#{h['name']}'
				, '#{h['contractor_id']}'
				, '#{h['rate']}'
				)
		SQL
	end
end
