#! /usr/bin/perl

# --------------------------------------------------------------- #
# EXL_CLOUD_STATUS.PL - Get ExLibris Cloud Status Information     #
#                                                                 #
# Version 0.2 08.04.2015                                          #
# (c) St.Lohrum <lohrum@zib.de>, Zuse Institu Berlin              #
#                                                                 #
# This program return ExLibris cloud status information, given by #
# status.exlibrisgroup.com. IP address has to be registered with  #
# ExLibris.                                                       #
#                                                                 #
# Optionally a Nagios compliant status code & message will be     #
# generated.                                                      #
# --------------------------------------------------------------- #
BEGIN { $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0 }
use strict;
use Getopt::Std;
use LWP::Simple;
use XML::Simple;
use Data::Dumper;

my $EXIT_OK       = 0;
my $EXIT_WARNING  = 1;
my $EXIT_CRITICAL = 2;
my $EXIT_UNKNOWN  = 3 ;

my %CLOUD_CODE;
$CLOUD_CODE{'OK'}      = $EXIT_OK;
$CLOUD_CODE{'PERF'}    = $EXIT_CRITICAL;
$CLOUD_CODE{'ERROR'}   = $EXIT_CRITICAL;
$CLOUD_CODE{'MAINT'}   = $EXIT_WARNING;
$CLOUD_CODE{'SERVICE'} = $EXIT_WARNING;
   

my $url       = 'https://status.exlibrisgroup.com/?page_id=5511';
my $type      = 'help';
my $value     = '';

my $HELPTEXT ="
EXL_CLOUD_STATUS.PL - Get ExLibris Cloud Status Information

(c) St.Lohrum <lohrum\@zib.de>, 27.03.2015, Zuse Institu Berlin 

This program return ExLibris cloud status information, given by
status.exlibrisgroup.com. IP address has to be registered with
ExLibris.
    
Usage: exl_cloud_status.pl [-n] [-r region] [-s service] [-e env1,env2,...] 
                           [-b pos] [-x] [-p] [-q] [-l] [-c] [-h]
    
Options:
  -r region   'Europe', 'North America', 'Asia'           
  -s service  'Primo', 'Primo Central', 'Metalib+', 'Alma', 'SFX', 'bX'
  -e envs     Comma separated list with ExLibris vnvironment codes, e.g.
                'PC CR01',    - >  Primo Central Environment         
                'MLPlus CR01'  ->  Metalib Plus Environment

  -n          create NAGIOS compliant meassage (will only work if
              exactly one record is returned.          

  -h          print little help text
                           
Debugging options:                           
  -x          run XMP parser XML::Simple and dump tree
  -p          print returned XML
  -q          print URL request
  -b pos      print XML and break it at position <pos>         
  -l          print returned XML and break lines at each closing tag 
  
  -c          cleanup XML before processing  

The options -r -s -e  are mutually exclusive, one of them is required. 
If none of the options -x -p -b -l is set, default will be option -p
Options -c or -b will remove line breaks \\r\\n befrore parsing or printing 
  
";

# -- Command line options --------------------------------------
my %opts = {};
getopts ('s:r:e:b:ncxhlpq', \%opts);
if (defined $opts{'r'} ) { $value = $opts{'r'}; $type = 'region';  }
if (defined $opts{'s'} ) { $value = $opts{'s'}; $type = 'service'; }
if (defined $opts{'e'} ) { $value = $opts{'e'}; $type = 'envs';    }
if (defined $opts{'n'} ) { $opts{'c'} = ' '; } 
if ($type eq "help") { print $HELPTEXT; exit 1; }
if (not (defined $opts{'l'} || defined $opts{'p'} || defined $opts{'x'} || defined $opts{'b'})) { $opts{'p'} = ' '; }


# -- Get XML from Exlibris Cloud status page -------------------
my $browser = LWP::UserAgent->new(agent => "Mozilla/5.0 (X11; Linux x86_64; rv:39.0) Gecko/20100101 Firefox/39.0",);
   #$browser->ssl_opts(verify_hostname => 0);
   #$browser->ssl_opts(SSL_verify_mode => 0x00);
my $result  = $browser->post($url, [act=>'get_status', $type=>$value, client=>'xml',]); 

if ($result->is_error && $result->code != 406) {
    my $error_message = sprintf("HTTP error [%d] %s", $result->code, $result->message);
    if (not defined $opts{'n'}) { die $error_message; }
    print $error_message;
    exit($EXIT_UNKNOWN);
}

my $xmlstr  = $result->decoded_content;

# print "***", $xmlstr, "***\n";
if ($xmlstr eq "") {  
   print "no result or cannot access ExLibris status page\n"; 
   exit ($EXIT_UNKNOWN);
}    


# -- Print HTTP request ----------------------------------------
if (defined $opts{'q'}) {
   print $url, "\n";
}


# -- Cleanup XML before processing -----------------------------
if (defined $opts{'c'}) {
  $xmlstr =~ s#\r\n#\n#g;
  $xmlstr =~ s#<message>#<message><![CDATA[#;
  $xmlstr =~ s#</message>#]]></message>#;

#  my @xmlarr  = split("\r\n",  $xmlstr);
#  $xmlstr  = join(' ', @xmlarr);

#  $xmlstr =~ s#<br />##g;
#  $xmlstr =~ s#<br>##g;

#  $xmlstr =~ s#</div>##g;
#  $xmlstr =~ s#<div>##g;
#  $xmlstr =~ s#<div id="imcontent">##g;

#  $xmlstr =~ s#<p>##g;
#  $xmlstr =~ s#</p>##g;
#  $xmlstr =~ s#</p<#<#g;

#  $xmlstr =~ s#<b>##g;
#  $xmlstr =~ s#</b>##g;
#  $xmlstr =~ s#&nbsp;##g;
}


# -- Create NAGIOS compliant message ---------------------------
if (defined $opts{'n'}) {
  my @xmlarr  = split("\n",  $xmlstr);
  $xmlstr  = join(' ', @xmlarr);
  @xmlarr  = split("\r",  $xmlstr);     
  $xmlstr  = join(' ', @xmlarr);
  $xmlstr  =~ s#  *# #g;
    
  my $xml = new XML::Simple;
  my $data = $xml->XMLin($xmlstr);
           
  my $cloud_id       = $data->{'instance'}->{'id'};
  my $cloud_status   = $data->{'instance'}->{'status'};
  my $cloud_service  = $data->{'instance'}->{'service'};
  my $cloud_region   = $data->{'instance'}->{'region'}; 
  my $cloud_schedule = $data->{'instance'}->{'schedule'};
  my $cloud_message  = $data->{'instance'}->{'message'};
  $cloud_id       =~ s/|//g;
  $cloud_status   =~ s/|//g;
  $cloud_service  =~ s/|//g;
  $cloud_region   =~ s/|//g;
  $cloud_schedule =~ s/|//g;
  $cloud_message  =~ s/|//g;

  
  my $message = '';   
  if ($cloud_id eq '') { 
      $message = "None or multiple) cloud environments found for request $type = $value";
      print $message;
      exit($EXIT_UNKNOWN);
  }
  
  # $message =  sprintf("%s (%s,%s) ", $cloud_id, $cloud_service, $cloud_region);
  $message =  sprintf("%s (%s) ", $cloud_service, $cloud_id);
  $message .= "\n" . $cloud_message  if ($cloud_message  ne '');
  $message .= "\n" . $cloud_schedule if ($cloud_schedule ne '');
  
  
  if ($cloud_status eq 'OK') {   
     if ($cloud_schedule ne '') { $cloud_status = 'MAINT'; }
     print 'OK: ', $message;
     exit($CLOUD_CODE{$cloud_status});
  }
  
  if ($cloud_status eq 'PERF') {
      print $cloud_status, ': ', $message;
      exit($CLOUD_CODE{$cloud_status}); 
  }
  
  if ($cloud_status eq 'MAINT') {
      print $cloud_status, ': ', $message;     
      exit($CLOUD_CODE{$cloud_status});   
  } 

  if ($cloud_status eq 'SERVICE') {
      print $cloud_status, ': ', $message;     
      exit($CLOUD_CODE{$cloud_status});   
  } 
  
  if ($cloud_status eq 'ERROR') {  
     print $cloud_status, 'OK: ', $message;
     exit($CLOUD_CODE{$cloud_status});
  }
 
  $message = sprintf("Unknown status code %s. %s", $cloud_status, $message); 
  print $message;
  exit ($EXIT_UNKNOWN);
                  
}            


# -- Print returned XML ----------------------------------------
if (defined $opts{'p'}) {
    print $xmlstr, "\n\n\n";
}


# -- Print XML and break it at position <number> ---------------
if (defined $opts{'b'}) {
   my @xmlarr  = split("\r\n",  $xmlstr);
   $xmlstr  = join(' ', @xmlarr); 
   print substr($xmlstr, 0, $opts{'b'}), "\n\n\n";
   print substr($xmlstr, $opts{'b'}, 1000), "\n\n\n";
}   


# -- Print XML and break lines at each closing tag -------------
if (defined $opts{'l'}) {
   my @xmlarr  = split(">",  $xmlstr);
   for my $line (@xmlarr) { print $line, ">\n"; }
}


# -- Parse XML and dump tree ----------------------------------- 
if (defined $opts{'x'}) {
  my @xmlarr  = split("\r\n",  $xmlstr);
  $xmlstr  = join(' ', @xmlarr);
  my $xml = new XML::Simple;
  my $data = $xml->XMLin($xmlstr);
  print Dumper( $data );

  print "Instance: ", $data->{'instance'}->{'id'},       "\n";
  print "Status:   ", $data->{'instance'}->{'status'},   "\n";
  print "Service:  ", $data->{'instance'}->{'service'},  "\n";
  print "Region:   ", $data->{'instance'}->{'region'},   "\n";
  print "Schedule: ", $data->{'instance'}->{'schedule'}, "\n";
  print "Message:  ", $data->{'instance'}->{'message'},  "\n";

  # print keys %($data->{'instance'}), "\n" ;
  for (keys %$data)  { print $_, "\n" ;} 
}
