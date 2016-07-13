# Freshbooks-dashboard
Requirements:
- MySQL 14.14 / Distribu 5.5.40
- Ruby 2.0.0-p481
- Gems:
  - nokogiri
  - mysql2
  - awesome_print

Installation:

1) Download files here

2) If you don’t have required gems, copy and run in your terminal:

	- gem install nokogiri
	etc.

3) From you terminal:
	- cd path/to/folder

Configuration:

1) Edit ./lib/FetchFreshbooks.rb
  - add your api key and freshbooks subdomain on lines 19 and 20
  - edit Freshbooks querys as needed

2) Edit ./lib/StoreData.rb
  - add your servers information on lines 40-43 and test sever information on lines 48-51
  - change the output server, set DBCHOICE = 'mysql' for your live server and DBCHOICE = 'mysqltest' for your test server.
  - Edit SQL tables and view as needed

3) Depending on your MySQL version you may need to: SET sql_mode = ‘’;

Usage:
To run in your terminal type: "ruby invoke.rb"

Output:
Saves parsed XML data to MySQL server
