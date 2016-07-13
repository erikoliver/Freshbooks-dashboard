# By Erik Oliver
#
# License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)
# (C) 2016 Richardson Oliver Law Group

require 'rubygems'
require 'nokogiri'

class ParseFreshbooks

	# Query Freshbooks to determine the number of invoices since the update_since string
	# Input: updated_since = "YYYY-MM-DD", update_since defaults to "2000-01-01" with no input
	# returns: Array of XML results, e.g. [<page1 XML string>, <page2 XML string>]
	def get_invoice_pages(updated_since = "2000-01-01", page)
		fb_new = FetchFreshbooks.new
		tmp = fb_new.date_query(updated_since, page)
		body = fb_new.fetch_XML(tmp)
		doc = Nokogiri::XML(body)
		return doc
	end

	# Query Freshbooks to an XML body, parse it for data, and store it individually
	# Input:update_since string to only grab pages with new information, dbhandle = StoreData.new()
	# updated_since = "YYYY-MM-DD"
	# Outputs: returns true when all pages have been parsed and stored
	def get_all_invoices(updated_since, dbhandle)
		page = 1
		numpages = nil
		check_date = dbhandle.last_line_modified_date

		begin
			print "Starting to get invoice page #{page}\n"
				doc = get_invoice_pages(updated_since, page)
				numpages = doc.css("invoices").first["pages"].to_i if (numpages == nil)
				doc.css('invoice').each do |invoice|
					h = Hash.new()

					%w[organization updated date amount_outstanding invoice_id number discount status].each do |key|
						invoice.css("#{key}").each do |element|
							h[key] = element.text if (! h.has_key?(key))
						end
					end
					h['amount'] = get_amount(invoice)
					h['matter'] = get_matter(invoice)
					if(check_date != nil)
						if(string_to_date(check_date) >= string_to_date(updated_since)) #<------------------------ make toggle
							get_invoice_lines(dbhandle, invoice)
						end
					else
							get_invoice_lines(dbhandle, invoice)
					end
					#updates invoice
					if(check_date != nil)
						if(string_to_date(check_date) >= string_to_date(updated_since)) # <------------------------------- make toggle
							dbhandle.invoice_updateinsert(h)
						end
					else
						dbhandle.invoice_updateinsert(h)
					end
				end

			print "...finished with invoice page #{page}\n"
			page += 1
		end while(numpages != nil && page <= numpages)
		return true
	end

	#Check Data type of date. If date is type DATE it returns it if it of type STRING it converts it to a date
	#this is here because when we check for the last date in the database mysql returns type DATE and sqlite returns type STRING
	#INPUTS: node =  '00-00-0000' or 00-00-0000
	#OUTPUTS:a date of type DATE
	def string_to_date(node)
		if(node.class == Date)
			return node
		else
			return Date.parse(node)
		end
	end

	#Funtion is called in get_all_invoices and uses the get_all_invoices Freshbooks query
	#INPUTS: dbhandle to allow it to access the StoreData class
	#invoice = "invoice"
	#OUTPUTS: data goes to the database directly and nothing is returned
	def get_invoice_lines(dbhandle, invoice)
		invoice.css('lines line').each do |line|
			h = Hash.new()
			%w[line_id order name unit_cost quantity amount description type].each do |key|
			  line.css("#{key}").each do |element|
				h[key] = element.text if (! h.has_key?(key))
			  end # line.css do
			end # %w.each

			if(h['description'] != nil && h['description'] != "")
				h['description'] = h['description'].gsub(/'/, "''").gsub(/"/,'""')
			end

			h['first_time_entry_id'] = get_time_entry_id(line)
			h['first_expense_id'] = get_expense_id(line)

			if(h['description'] != nil && h['description'] != "")
				h['line_item_date'] = get_line_item_date(line)
				h['person'] = get_person(line) if(h['description'] != nil && h['description'] != "")
				h['person'] = h['person'].gsub(/:/,'')
			else
				h['line_item_date'] = ''
				h['person'] = ''
			end

			h['invoice_id'] = get_invoice_id(invoice)
			h['number'] = get_line_number(invoice)
			h['matter'] = get_line_matter(line, invoice)
			h['updated'] = get_line_update(invoice)
			dbhandle.invoice_line_updateinsert(h)
		end #invoice.css.each
	end # get_invoice_lines

	#Separately parse "expense_id" from get_invoice_lines
	#Inputs: "lines line"
	#Output: expense_id.text
	def get_expense_id(line)
		expense_id = line.css('expense_id')
#NOTE return value now needs to be an integer
		return expense_id.text.to_i
	end

	#pulls a name out of the "description" field with a regex
	#Inputs: "lines line"
	#Output: person if(person != nil)

	def get_person(line)
		person_regex = /([A-Z]{1}[a-z]+\s[A-Z]{1}[a-z]+[:])/

		person = nil

		line.css('description').each do |desc|
			if(person_regex.match(desc.text)) then

				person = $1
				break
			end
		end
		return person if(person != nil)

		return 'no name found'

	end

	#Separately parse "time_entry_id" from get_invoice_lines
	#Inputs: "lines line"
	#Output: time_entry_id.text
	def get_time_entry_id(line)
		time_entry_id = line.css('time_entries time_entry time_entry_id')
#NOTE return value now needs to be an integer
		return time_entry_id.text
	end

	#pulls a date out of the "description" field with a regex
	#Inputs: "lines line"
	#Output: date if(date != nil)
	def get_line_item_date(line)
		date_regex = /([0-9]{2}\/[0-9]{2}\/[0-9]*)/

		date = nil

		line.css('description').each do |desc|
			if(date_regex.match(desc.text)) then
				date = $1
				break
			end
		end
		return date if(date != nil)

		if(date == nil)
			return 'no date found'
		end
	end

	#Separately parse "invoice_id" from get_invoice_lines
	#Inputs: "invoice"
	#Output: invoice_id.text
	def get_invoice_id(invoice)
		invoice_id = invoice.css('invoice_id')
		return invoice_id.text
	end

	#Separately parse "number" from get_invoice_lines
	#Inputs: "invoice"
	#Output: number.text
	def get_line_number(invoice)
		number = invoice.css('number')
		return number.text
	end

	#Separately parse 'matter' from get_invoice_lines
	#first applies a regex to the description field,
	#once found it stops the loop and returns the matter number, if it doesn't find it in the description it looks in
	#the name field and applies a regex to it, if it doesn't find it there it checks to see if the organization is
	#a 'Sample Organization' it returns "FIRM-G0001"
	#if it's not a sample organization it returns an error message
	#INPUTS: 'lines line' through node
	#invoice = 'invoice' field
	#OUTPUTS: matter number or error message
	def get_line_matter(node, invoice)
		matterregex = /([A-Z]{4}-[A-Z][0-9]{4}\S*)/

		# Check all invoice lines for matter #s, stop after first match
		matter = nil
		node.css('description').each do |desc|
			if(matterregex.match(desc.text)) then
				# we found a match
				matter = $1
				break
			end #if
		end # each description

		# return what we found
		return matter if(matter != nil)

		# having failed at finding a matter in the description can we find one in a 'name' element?

		node.css('name').each do |desc|
			if(matterregex.match(desc.text)) then
				# we found a match
				matter = $1
				break
			end # if
		end # each name

		# return what we found
		return matter if(matter != nil)

		organization = invoice.css('organization').first.text
		return 'FIRM-G0001' if (organization == 'Sample Organization')
		# third strategy see if the current organization == Sample
		# organization, if so set matter to FIRM

		return 'error no matter found'
	end

	#Separately parse "updated" from get_invoice_lines
	#Inputs: "invoice"
	#Output: updated.text
	def get_line_update(invoice)
		update = invoice.css('updated')
		return update.text
	end

	#Separately parse "amount" from get_all_invoices to get only the first "amount" field
	#Inputs: "amount"
	#Output: amount.text
	def get_amount(node)
		amount = node.css('amount').first
		return amount.text
	end

	#Separately parse 'matter' from get_all_invoices
	#first applies a regex to the description field,
	#once found it stops the loop and returns the matter number, if it doesn't find it in the description it looks in
	#the name field and applies a regex to it, if it doesn't find it there it checks to see if the organization is
	#a 'Sample Organization' it returns "FIRM-G0001"
	#if it's not a sample organization it returns an error message
	#INPUTS: XML field through node
	#OUTPUTS: matter number or error message
	def get_matter(node)
		matterregex = /([A-Z]{4}-[A-Z][0-9]{4}\S*)/

		# Check all invoice lines for matter #s, stop after first match
		matter = nil
		node.css('lines line description').each do |desc|
			if(matterregex.match(desc.text)) then
				# we found a match
				matter = $1
				break
			end #if
		end # each description

		# return what we found
		return matter if(matter != nil)

		# having failed at finding a matter in the description can we find one in a 'name' element?

		node.css('lines line name').each do |desc|
			if(matterregex.match(desc.text)) then
				# we found a match
				matter = $1
				break
			end # if
		end # each name

		# return what we found
		return matter if(matter != nil)

		# third strategy see if the current organization == Sample
		# organization, if so set matter to FIRM
		organization = node.css('organization').first.text
		return 'FIRM-G0001' if (organization == 'Sample Organization')

		# ok we've had no luck return error
		return 'error no matter found'
	end

	# Query Freshbooks by page for XML body
	# INPUTS: page number
	# OUTPUTS: Array of XML results, e.g. [<page1 XML string>, <page2 XML string>]
	def get_project_page(page)
		fb_new = FetchFreshbooks.new()
		body = fb_new.fetch_XML(fb_new.project_query(page))
		doc = Nokogiri::XML(body)
		return doc
	end

	#calls get_project_page to individually parse and store each XML body
	#it increments page until it equals the total number of pages (numpages)
	#INPUTS: dbhandle to allow access to StoreData
	#OUTPUTS: return true when all pages are parsed and stored

	def get_all_projects(dbhandle)
		page = 1
		numpages = nil
		projlist=Hash.new()
		begin
			print "Starting to get project page #{page}\n"
			doc = get_project_page(page)
			numpages = doc.css("projects").first["pages"].to_i if (numpages == nil)
			doc.css('project').each do |project|
				h = Hash.new()
				#NOTE deleted hour_budget field
				%w[name project_id].each do |key|
					project.css("#{key}").each do |element|
						h[key] = element.text if (! h.has_key?(key))
					end
				end
				#XML file no longer has an hours_budget field
				#its been changed to (budget hours)
				project.css('budget hours').each do |el|
					h['hour_budget'] = el.text
				end
            h['name'].match(/([A-Z]{4}-[A-Z][0-9]{4}\S*)/)
            h['matter'] =  $1
                # avoid duplicate matters in project list
        if(! projlist.has_key?($1)) then
					projlist[$1] = true
					dbhandle.project_insert(h)
				end
			end
			print "...finished with projects #{page}\n"
			page += 1
		end while (numpages != nil && page <= numpages)
		return true
	end

	# Retrive XML body to be parsed and stored later in get_last_95_days_of_time_entries
	# INPUTS: page number
	# OUTPUTS: XML body
	def grab_time_entry_page(page)
		fb_new = FetchFreshbooks.new
		body = fb_new.fetch_XML(fb_new.time_entry_query(page))
		doc = Nokogiri::XML(body)
		return doc
	end

	#calls grab_time_entry_page to individually parse and store each time entry XML body
	#iterates until the oldest date found in an XML body is larger than the target date
	#INPUTS: dbhandle to allow it to access the StoreData class
	#OUTPUTS: return true when all pages are parsed and stored
	def get_last_95_days_of_time_entries(dbhandle)
		page = 1
		numpages = nil
		oldest = Date.today
		target = Date.today - 95
		results = Array.new()

		begin
			print "Starting to get time_entry page #{page}\n"
			doc = grab_time_entry_page(page)
			numpages = doc.css("time_entries").first["pages"].to_i if (numpages == nil)
			doc.css('time_entry').each do |time_entry|
				h = Hash.new()
				%w[time_entry_id staff_id project_id task_id hours date notes billed].each do |key|
					time_entry.css("#{key}").each do |element|
						h[key] = element.text if (! h.has_key?(key))
					end
				end

				tempdate = Date.parse(time_entry.css('date').text)
				oldest = tempdate if(tempdate < oldest)

				h['notes'] = h['notes'].gsub(/'/, "''").gsub(/"/,'""')

				dbhandle.time_entry_insert(h)
			end
			print "...finished with time_entry page #{page}\n"

			page += 1

		end while (oldest >= target && numpages != nil && page <= numpages)

		return results
	end

	# Retrive XML body to be parsed and stored later in get_staff_entries
	# INPUTS: page number
	# OUTPUTS: XML body
	def get_staff_page(page)
		fb = FetchFreshbooks.new()
		staff_page = fb.fetch_XML(fb.staff_query(page))
		doc = Nokogiri::XML(staff_page)
		return doc
	end

	#calls get_staff_page to individually parse and store each XML body
	#it increments page until it equals the total number of pages (numpages)
	#INPUTS: dbhandle to allow access to StoreData
	#OUTPUTS: return true when all pages are parsed and stored
	def get_staff_entries(dbhandle)
		page = 1
		numpages= nil
		# results = Array.new()
		begin
			print "Starting to get staff page #{page}\n"
				doc = get_staff_page(page)
				numpages = doc.css("staff_members").first["pages"].to_i if (numpages == nil)
				# parse each invoice separately
				doc.css('member').each do |staff|
					h = Hash.new()
					%w[staff_id first_name last_name rate].each do |key|
						staff.css("#{key}").each do |element|
							h[key] = element.text if (! h.has_key?(key))
						end
					h['person'] = "#{h['first_name']} #{h['last_name']}"
					end
					dbhandle.staff_insert(h)
				end
				print "...finished with staff page #{page}\n"
				page += 1

		end	while(numpages != nil && page <= numpages)
		#	return results
		return true
	end

	# Retrive XML body to be parsed
	# INPUTS: page number
	# OUTPUTS: XML body

	def get_deleted_invoice_page(updated_since = "2000-01-01", page)
		fb_new = FetchFreshbooks.new
		tmp = fb_new.deleted_query(updated_since, page)
		body = fb_new.fetch_XML(tmp)
		doc = Nokogiri::XML(body)
		return doc
	end

	#calls get_deleted_invoice_page to individually parse and store each XML body
	#it increments page until it equals the total number of pages (numpages)
	#funciton is called in invoke.rb
	#INPUTS: date to retrieve deleted numbers from last 30 days
	#OUTPUTS: return array of deleted invoice ids
	def get_deleted_invoices(updated_since)
		page = 1
		numpages = nil
		array = Array.new()
		begin
				doc = get_deleted_invoice_page(updated_since, page)
				numpages = doc.css("invoices").first["pages"].to_i if (numpages == nil)
				doc.css('invoice').each do |invoice|
					del_invoice_id = invoice.css('invoice_id').text
					array << del_invoice_id
				end
			page += 1
		end while(numpages != nil && page <= numpages)
		return array
	end

	# Retrive XML body to be parsed and stored later in get_all_contractors
	# INPUTS: page number
	# OUTPUTS: XML body

	def get_contractor_page(page)
		fb_new = FetchFreshbooks.new
		body = fb_new.fetch_XML(fb_new.contractor_query(page))
		doc = Nokogiri::XML(body)
		return doc
	end

	#calls get_contractor_page to individually parse and store each XML body
	#it increments page until it equals the total number of pages (numpages)
	#INPUTS: dbhandle to allow access to StoreData
	#OUTPUTS: return true when all pages are parsed and stored
	def get_all_contractors(dbhandle)
		page = 1
		numpages= nil

		begin
			print "Starting to get contractor page #{page}\n"
			doc = get_contractor_page(page)
			numpages = doc.css("contractors").first["pages"].to_i if (numpages == nil)
			doc.css("contractor").each do |contractor|
				h = Hash.new()
				%w[name contractor_id rate].each do |key|
					contractor.css("#{key}").each do |element|
						h[key] = element.text if (! h.has_key?(key))
					end
				end
				dbhandle.contractor_insert(h)
			end
			print "...finished with contractor page #{page}\n"
			page += 1
		end while (numpages != nil && page <= numpages)

		return true
	end

end
