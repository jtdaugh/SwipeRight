require 'rubygems'
require 'uri'
require 'net/http'
require 'parse-ruby-client'
require 'active_support/all'
require 'nokogiri'
require 'mail'

MAX_PER_CITY = 9

parseID = "DaJkkAOKSFVxqPbI7gyPluuqRWkUgGIgzDzMJhUD"
parseREST = "Hy5vzkrQd3U4ksKVjn0yW697KWFCyaOCVznLe9Qo"

FF_ADMIN_USER_ID = "flightfinder"
FF_ADMIN_PASSWORD = "fuckkayak"

SENDGRIP_USER_ID = "jtdaugh"
SENDGRID_PASSWORD = "fuckkayak"

# TRAVELOCITY RSS FEED LINK FORMAT
# http://www.travelocity.com/dealservice/globaltrips-shopping-svcs/deals-1.0/services/RssDealsServices?ProductType=Air&rdr=GEN&nm=My~Travelocity~Specials&typ=0&orig=NYC&dest=MIA,SAN,QDF,DTW
# Returns content containing link:
# http://travel.travelocity.com/flights/InitialSearch.do?Service=TRAVELOCITY&flightType=roundtrip&dateTypeSelect=plusMinusDates&adults=1&returnDateFlexibility=3&departDateFlexibility=3&leavingFrom=NYC&goingTo=DTW&leavingDate=06/01/2013&returningDate=06/03/2013


Parse.init :application_id => parseID,
           :api_key        => parseREST

HOTEL_KEYS = ["cbq2aqrfn9k93tw7e23x934m",
              "hf8br596p8sy9ahvc2yu466a",
              "d5tcnqy2ncb8bv5cdkss7r47",
              "cq9t5q9r8z9cnym5syrp7zgg",
              "w4k755s7wsxm4dks5xm74dfe",
              "bynsqz35cd6qjr9yncw7njb6",
              "9hvn6y95ta28dhvefdrzyze4",
              "pcesfbsj4krs7duc2bdvuaqr",
              "9qqzvr7d6qgn33g78uetmtkn",
              "h3dunfvr6y3pznr9hw9wgdkj"]

class Cities
  @@images = Array.new #static CityImages array [[apt,url],[apt,url],...]

  attr_accessor :aptCode
  attr_accessor :city
  attr_accessor :state
  attr_accessor :imgUrl

  def initialize(a,l)
    @aptCode = a 
    @city = l.to_s.split(', ')[0]
    @state = l.to_s.split(', ')[1]  
    @imgUrl = "unset"  
  end

  def getImage
    if @@images.size == 0
      Cities.getAllImages
    end

    @@images.each do |parseObj|
      if parseObj["airportCode"] == @aptCode
        @imgUrl = parseObj["imageUrl"]
        break
      end
    end

    if @imgUrl == "unset"
      newImageSearch
    end
  end
  
  def self.getAllImages
    # Query parse and store into @@images class var
    # puts "getting all images"
    cityImagesQuery = Parse::Query.new("CityImages")
    cityImagesQuery.limit = 500
    @@images = cityImagesQuery.get
  end

  def newImageSearch
    # Use an image search api
    urlifiedName = city.gsub(" ",'_').gsub("/","_")
    imgSearchUrl = "http://ajax.googleapis.com/ajax/services/search/images?v=1.0&q=#{urlifiedName}&as_sitesearch=commons.wikimedia.org&"
    puts "searching for image with url: #{imgSearchUrl}" 
    uri = URI(imgSearchUrl)
    results = Net::HTTP.get(uri)
    parsed = JSON.parse(results)
    imageEmailHtml = ""
    emailSubject = "" 
    if (parsed && parsed["responseData"] && parsed["responseData"]["results"] && parsed["responseData"]["results"].size > 0)
      added = false
      parsed["responseData"]["results"].each do |imgInfo|
        w = imgInfo["width"].to_i
        h = imgInfo["height"].to_i
        url = imgInfo["url"]
        if (w <= 1000 && h <= 1000)
          imageEmailHtml << "<b>Image added into Parse.</b>"
          imageEmailHtml << "<br>City: #{@city}, #{@state}"
          imageEmailHtml << "<br>Code: #{@aptCode}"
          imageEmailHtml << "<br>URL : #{url}"
          imageEmailHtml << "<br>Size: #{w} x #{h}"
          emailSubject << "Found New CityImage!"
          @imgUrl = url
          added = true
          break
        end
      end
      if (added == false)
        imageEmailHtml << "<b>CityImage lookup failed...</b>"
        imageEmailHtml << "<br>City: #{@city}, #{@state}"
        imageEmailHtml << "<br>Code: #{@aptCode}"
        emailSubject << "[ACTION REQUIRED]: Need to add new CityImage"
      end
    else
      imageEmailHtml << "<b>CityImage lookup failed...</b>"
      imageEmailHtml << "<br>City: #{@city}, #{@state}"
      imageEmailHtml << "<br>Code: #{@aptCode}"
      emailSubject << "[ACTION REQUIRED]: Need to add new CityImage"
    end
    newParseImg = Parse::Object.new("CityImages")
    newParseImg["airportCode"] = @aptCode
    newParseImg["imageUrl"] = @imgUrl
    puts emailSubject
    puts imageEmailHtml
    emailResults(imageEmailHtml,emailSubject)
    @@images.push(newParseImg)
    newParseImg.save
  end

end

class Deal
  
  attr_accessor :origin
  attr_accessor :destination
  attr_accessor :departDate
  attr_accessor :returnDate
  attr_accessor :price
  attr_accessor :hotelPrice
  attr_accessor :airline
  attr_accessor :airLink
  attr_accessor :hotelLink2
  attr_accessor :hotelLink
  attr_accessor :source

  def initialize(oCode,oCity,dCode,dCity,depart,retrn,p,a,src)
    @origin = Cities.new(oCode,oCity)
    @destination = Cities.new(dCode,dCity)
    @departDate = DateTime.strptime(depart,"%m/%d/%Y")
    @returnDate = DateTime.strptime(retrn,"%m/%d/%Y")
    @price = p
    @airline = a
    @source = src
  end

  def self.newFromKayak(dealXML)
    newDeal =self.new(dealXML.xpath("kyk:originCode").inner_text,
                      dealXML.xpath("kyk:originLocation").inner_text,
                      dealXML.xpath("kyk:destCode").inner_text,
                      dealXML.xpath("kyk:destLocation").inner_text,
                      dealXML.xpath("kyk:departDate").inner_text,
                      dealXML.xpath("kyk:returnDate").inner_text,
                      dealXML.xpath("kyk:price").inner_text,
                      dealXML.xpath("kyk:airline").inner_text,
                      "kayak")
  end

  def tripLength
    return (returnDate - departDate).to_i
  end

  def inFuture?
    return (departDate - DateTime.now) > 1 ? 1 : 0
  end

  def findHotel i
    hotelQueryUrl = "http://api.ean.com/ean-services/rs/hotel/v3/list?cid=55505&minorRev=16&apiKey=#{HOTEL_KEYS[i % HOTEL_KEYS.size]}&locale=en_US&currencyCode=USD&"
    hotelQueryUrl << "arrivalDate=#{departDate.strftime("%m/%d/%Y")}&departureDate=#{returnDate.strftime("%m/%d/%Y")}&room=1&"
    cityStr = destination.city.gsub(" ",'%20')
    stateStr = destination.state.gsub(" ","")
    hotelQueryUrl << "destinationString=#{cityStr + "," + stateStr}&numberOfResults=1&sort=PRICE&minStarRating=3.0"
    hotelUri = URI(hotelQueryUrl)
   
    hotelData = Net::HTTP.get(hotelUri)
    parsed = JSON.parse(hotelData)

    if (parsed && 
        parsed["HotelListResponse"] && 
        parsed["HotelListResponse"]["HotelList"] && 
        parsed["HotelListResponse"]["HotelList"]["HotelSummary"] &&
        parsed["HotelListResponse"]["HotelList"]["HotelSummary"]["RoomRateDetailsList"] && 
        parsed["HotelListResponse"]["HotelList"]["HotelSummary"]["RoomRateDetailsList"]["RoomRateDetails"] &&
        parsed["HotelListResponse"]["HotelList"]["HotelSummary"]["RoomRateDetailsList"]["RoomRateDetails"]["RateInfos"] &&
        parsed["HotelListResponse"]["HotelList"]["HotelSummary"]["RoomRateDetailsList"]["RoomRateDetails"]["RateInfos"]["RateInfo"] &&
        parsed["HotelListResponse"]["HotelList"]["HotelSummary"]["RoomRateDetailsList"]["RoomRateDetails"]["RateInfos"]["RateInfo"]["ChargeableRateInfo"] &&
        parsed["HotelListResponse"]["HotelList"]["HotelSummary"]["RoomRateDetailsList"]["RoomRateDetails"]["RateInfos"]["RateInfo"]["ChargeableRateInfo"]["@maxNightlyRate"]) then
      @hotelPrice = parsed["HotelListResponse"]["HotelList"]["HotelSummary"]["RoomRateDetailsList"]["RoomRateDetails"]["RateInfos"]["RateInfo"]["ChargeableRateInfo"]["@maxNightlyRate"]
      @hotelPrice = @hotelPrice.to_i
    else
      return 1
    end
    sleep(1.1 / (HOTEL_KEYS.size * 5))
    
    @hotelLink = "https://www.room77.com/search.html?key=#{destination.city + "," + destination.state}&cin=#{departDate.strftime("%m.%d.%Y")}&cout=#{returnDate.strftime("%m.%d.%Y")}&r=1&g=2&utm_source=nowcation&utm_medium=cpc&utm_campaign=#{destination.city + "," + destination.state}#c=7&sd=asc&s=PRICE&d=10" 
    @hotelLink2 = "http://www.expedia.com/Hotel-Search#destination=#{destination.city + "," + destination.state}&startDate=#{departDate.strftime("%m/%d/%Y")}&endDate=#{returnDate.strftime("%m/%d/%Y")}&adults=1&star=50,30&sort=price"
    return 0
  end

  def genAirLink
    #just concatenation
    @airLink = "http://www.expedia.com/Flights-Search?trip=roundtrip&leg1=from:#{origin.aptCode},to:#{destination.aptCode},departure:#{departDate.strftime("%m/%d/%Y")}TANYT&leg2=from:#{destination.aptCode},to:#{origin.aptCode},departure:#{returnDate.strftime("%m/%d/%Y")}TANYT&passengers=children:0,adults:1,seniors:0,infantinlap:Y&options=cabinclass:coach,nopenalty:N,sortby:price&mode=search"
  end

end

def isDuplicate(thisDeal, oldDeals, newDeals)
  loc = (thisDeal.destination.city + ", " + thisDeal.destination.state)
  oldDeals.each do |deal|
    if ((loc == deal["destLocation"]) && (thisDeal.departDate.strftime("%m/%d/%Y") == deal["departDate"])) 
      return 1
    end
  end
  newDeals.each do |deal|
    if ((thisDeal.destination.city == deal.destination.city) && (thisDeal.departDate.strftime("%m/%d/%Y") == deal.departDate.strftime("%m/%d/%Y"))) 
      return 1
    end
  end
  return 0
end

def kayakRssRequest(origin, today, cityDeals, maxDeals, oldDeals) 

  possibleDeals = Array.new
  uri = URI("http://www.kayak.com/h/rss/buzz?code=#{origin}&tm=#{today.strftime("%Y%m")}")
  xml_data = Net::HTTP.get(uri)
  xml_doc  = Nokogiri::XML(xml_data)
  xml_doc.xpath("//item").each do |deal|
    possibleDeals.push(Deal.newFromKayak(deal))
  end
  possibleDeals.sort do |a,b| a.departDate <=> b.departDate end
  dealsAdded = 0
  hotelSkips = 0
  possibleDeals.each do |deal|
    len = deal.tripLength
    future = deal.inFuture?
    if (len > 2 && len < 12 && future == 1) then
      if (isDuplicate(deal, oldDeals, cityDeals) == 0)
        deal.genAirLink
        deal.destination.getImage
        hotelSkips += (deal.findHotel(dealsAdded))
        cityDeals.push(deal)
        dealsAdded += 1
        if (dealsAdded >= maxDeals) 
          break
        end
      end
    end
  end
  return hotelSkips
end

def getExistingDeals(city)
  existingQuery = Parse::Query.new("Deals")
  existingQuery.eq("originCode",city)
  existingQuery.order_by = "createdAt"
  existingDeals = existingQuery.get
  return existingDeals
end

def deleteOldDeals(city, toAdd, oldDeals)
  deleteLimit = oldDeals.size - (MAX_PER_CITY - toAdd)
  if (deleteLimit < 0) 
    deleteLimit = 0
  end
  r = deleteLimit - 1
  dealsToDelete = oldDeals[0..r]
  if (deleteLimit <= 0)
    dealsToDelete = []
  end
  deleteBatch = Parse::Batch.new
  dealsToDelete.each do |oldDeal|
    deleteBatch.delete_object(oldDeal)
  end
  deleteBatch.run!
  return dealsToDelete.size
end

def pushNewDeals deals
  batch = Parse::Batch.new
  deals.each do |deal|
    parseObj = Parse::Object.new("Deals")
    parseObj["airline"] = deal.airline
    parseObj["departDate"] = deal.departDate.strftime("%m/%d/%Y")
    parseObj["destCode"] = deal.destination.aptCode
    parseObj["destLocation"] = (deal.destination.city + ", " + deal.destination.state)
    parseObj["hotel_link"] = deal.hotelLink
    parseObj["hotel_price"] = deal.hotelPrice
    parseObj["imageUrl"] = deal.destination.imgUrl
    parseObj["link"] = deal.airLink
    parseObj["originCode"] = deal.origin.aptCode
    parseObj["originLocation"] = (deal.origin.city + ", " + deal.origin.state)
    parseObj["price"] = deal.price
    parseObj["source"] = deal.source
    parseObj["returnDate"] = deal.returnDate.strftime("%m/%d/%Y")
    batch.create_object(parseObj)
  end
  batch.run!
  return deals.size
end

def emailResults(emailOut,subj)
  Mail.defaults do
    delivery_method :smtp, { :address   => "smtp.sendgrid.net",
                           :port      => 587,
                           :domain    => "nowcation.com",
                           :user_name => SENDGRIP_USER_ID,
                           :password  => SENDGRID_PASSWORD,
                           :authentication => 'plain',
                           :enable_starttls_auto => true }
  end

  mail = Mail.deliver do
    to ['jtdaugh@umich.edu','jfsmills@umich.edu']
    from 'Nowcation <flightfinder@nowcation.com>'
    subject subj
    html_part do
      content_type 'text/html; charset=UTF-8'
      body emailOut
    end
  end
end

def getOriginCities
  originQuery = Parse::Query.new("Cities")
  originQuery.eq("active",true)
  return originQuery.get
end

def flightFinder
  startTime = DateTime.now
  totalDeleted = 0
  totalAdded = 0
  totalHotelSkips = 0
  emailOut = "<br>Runtime console output:<br>"
  Parse::User.authenticate(FF_ADMIN_USER_ID, FF_ADMIN_PASSWORD)
  originCities = getOriginCities
  originCities.each do |city|
    puts "\nSearching for: #{city["airport_code"]}"
    emailOut << "<br><br><b>Searching for: #{city["airport_code"]}</b>"
    cityDeals = Array.new
    existingDeals = getExistingDeals(city["airport_code"])
    hotelSkips = kayakRssRequest(city["airport_code"],DateTime.now, cityDeals, MAX_PER_CITY, existingDeals)
    totalHotelSkips += hotelSkips
    dealsAdded = cityDeals.size
    puts "#{city["airport_code"]} - #{DateTime.now.strftime("%B")}: Found #{dealsAdded} flight deals, Skipped #{hotelSkips} hotel deals."
    emailOut << "<br>#{city["airport_code"]} - #{DateTime.now.strftime("%B")}: Found #{dealsAdded} flight deals, Skipped #{hotelSkips} hotel deals."
    #do we need a second month?
    if (dealsAdded < MAX_PER_CITY)
      nextMonth = DateTime.now + 1.month
      hotelSkips = kayakRssRequest(city["airport_code"],nextMonth, cityDeals, MAX_PER_CITY - dealsAdded, existingDeals)
      totalHotelSkips += hotelSkips
      additionalDeals = cityDeals.size - dealsAdded
      puts "#{city["airport_code"]} - #{nextMonth.strftime("%B")}: Found #{additionalDeals} flight deals, Skipped #{hotelSkips} hotel deals."
      emailOut <<  "<br>#{city["airport_code"]} - #{nextMonth.strftime("%B")}: Found #{additionalDeals} flight deals, Skipped #{hotelSkips} hotel deals."
    end
    #do we need a third month?
    dealsAdded = cityDeals.size
    if (dealsAdded < MAX_PER_CITY)
      thirdMonth = DateTime.now + 2.month
      hotelSkips = kayakRssRequest(city["airport_code"],thirdMonth, cityDeals, MAX_PER_CITY - dealsAdded, existingDeals)
      totalHotelSkips += hotelSkips
      additionalDeals = cityDeals.size - dealsAdded
      puts "#{city["airport_code"]} - #{thirdMonth.strftime("%B")}: Found #{additionalDeals} flight deals, Skipped #{hotelSkips} hotel deals."
      emailOut << "<br>#{city["airport_code"]} - #{thirdMonth.strftime("%B")}: Found #{additionalDeals} flight deals, Skipped #{hotelSkips} hotel deals."
    end

    justDeleted = deleteOldDeals(city["airport_code"], cityDeals.size, existingDeals)
    justAdded = pushNewDeals(cityDeals)
    totalDeleted += justDeleted
    totalAdded += justAdded
    
    puts "Deleting #{justDeleted} old deals"
    emailOut << "<br>Deleting #{justDeleted} old deals"

    puts "Pushing #{justAdded} new deals"
    emailOut << "<br>Pushing #{justAdded} new deals"        
  
  end
  endTime = DateTime.now
  totalTime = ((endTime - startTime) * 24 * 60).to_i

  puts "\n-------------- Flight Finder Finished --------------"
  puts "#{totalDeleted} deals deleted" 
  puts "#{totalAdded} deals added"
  puts "#{totalHotelSkips} hotel deals skipped"

  email = "<b>Finished in #{totalTime} Minutes"  
  email << "<br>#{totalDeleted} deals deleted"
  email << "<br>#{totalAdded} deals added"
  email << "<br>#{totalHotelSkips} hotel deals skipped</b><br>"
  email << emailOut
  
  if (((totalAdded - totalDeleted) < 0) || totalHotelSkips >= 10) 
    emailResults(email,"Da Fuck, FF?")
  end
end

if __FILE__ == $0
  flightFinder
end
