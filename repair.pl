#!/usr/bin/perl

# Warnings/debugging packages
use strict;                   
use warnings;

# Static files
use File::Copy;
use XML::Simple;                        # Reading in XML files

# TeX related packages
use Text::BibTeX;                       

# Command line options
use Getopt::Long; 

### VARIABLES ###
my $senteXML_file   = 'references.xml'; 
my $bib_infile      = 'references.bib'; 
my $bib_outfile     = 'references_new.bib'; 
my $bib_tempfile    = 'temp.bib'; 
# Name of the Sente key field in the BibTeX file 
my $sente_key_field = 'citation_identifier'; 
# BibTeX entry types for web pages 
my @bibentry_web_types = ('webpage', 
                          'online',
                          'www',
                          'url'); 
my $bibentry_web_type_regex = join('|', @bibentry_web_types);    
# Name of Sente title fields in the Sente file
# Note: Order matters
my @sente_title_fields = ('articleTitle',      
                          'publicationTitle'); 
# Name of title fields in the bibtex file
# There are other title fields like 'Booktitle'; 
# Use 'title' only (for now)
my $bibtex_title_field = 'title';

### COMMAND LINE OPTIONS ### 
GetOptions ("sente-file:s"  => \$senteXML_file, 
            "bib-infile:s"  => \$bib_infile, 
            "bib-outfile:s" => \$bib_outfile)
     or die("Error in command line arguments.\n");

### READ IN DATA ###         
my $bib_data = new Text::BibTeX::File $bib_infile;

# Check that proper SenteXML file exists
my $sente_xml; 
my $sente_xml_data; 
my $sente_xml_exists = 0;               # Boolean indicator
my %sente_xml_data_mod;                 # Hash that cuts out some of the 
                                        #  hierarchy in the original XML file 
                                        #  for simpler code.
if (-e $senteXML_file)
{
    print "SenteXML file exists.\n"; 
    print "Reading in SenteXML file.\n"; 
    $sente_xml      = new XML::Simple; 
    $sente_xml_data = $sente_xml->XMLin($senteXML_file); 
    if (defined $sente_xml_data->{'xmlns'} && $sente_xml_data->{'xmlns'} =~ m/Sente/is)
    {
        $sente_xml_exists = 1; 
        print "SenteXML file ($senteXML_file) exists and has been properly read in.\n\n"; 

        # Use Sente key as the key in hash of data about each citation in Sente XML file
        SENTEXMLKEY: 
        foreach my $index (keys ($sente_xml_data->{'tss:library'}->{'tss:references'}->{'tss:reference'}))
        {
            my $new_key = $sente_xml_data->{'tss:library'}->{'tss:references'}->{'tss:reference'}->[$index]->{'tss:characteristics'}->{'tss:characteristic'}->{'Citation identifier'}->{'content'} || next SENTEXMLKEY; 
            my $new_content = $sente_xml_data->{'tss:library'}->{'tss:references'}->{'tss:reference'}->[$index]; 
            $sente_xml_data_mod{$new_key} = $new_content; 
        }
    }
    else
    {
        die("SenteXML file exists but is not properly formatted.\n"); 
    }
}
else
{
    die("SenteXML file does not exist.\n"); 
}

### MODIFY BIB FILE ###
print "Updating *.bib file ($bib_infile) ...\n"; 
# Write out in UTF-8 encoding
my $bib_data_temp = new Text::BibTeX::File $bib_tempfile, ">:encoding(UTF-8)";

BIBENTRY:
while (my $entry = new Text::BibTeX::Entry $bib_data)
{
    # Skip unless entry can be read
    next BIBENTRY unless $entry->parse_ok;
    # Skip unless it's possible to locate the Sente key for the reference 
    next BIBENTRY unless ($sente_xml_exists && defined $entry->get( $sente_key_field )); 
    # Can't use entry unless it has a type
    my $type = $entry->type() || next BIBENTRY;      

    if ( $type =~ m/$bibentry_web_type_regex/i &&    # If entry is a webpage
         ((!$entry->exists($bibtex_title_field)) ||  # That doesn't have a title already
            $entry->get($bibtex_title_field) ne ''  )
       )
    {
        my $sente_key = $entry->get( $sente_key_field ) || next BIBENTRY;
        print "Entry with Sente key $sente_key is a webpage: "; 
        # Try getting the title from the XML file and inserting it in the bibtex file
        SENTETITLE: 
        foreach my $sente_title_field (@sente_title_fields)
        {
            if (defined $sente_xml_data_mod{$sente_key}->{'tss:characteristics'}->{'tss:characteristic'}->{$sente_title_field}->{'content'}) 
            {
               my $title = $sente_xml_data_mod{$sente_key}->{'tss:characteristics'}->{'tss:characteristic'}->{$sente_title_field}->{'content'};
               $entry->set( 'title', $title );
               print "Fixed title field.\n"; 
               # Exit the loop as soon as one of the title fields works
               last SENTETITLE; 
            }
        }
        # Warn in case no title update was possible
        print "Unable to fix title field\n" 
            unless ($entry->exists($bibtex_title_field) &&    
                    $entry->get($bibtex_title_field) ne '');
    }
    $entry->write( $bib_data_temp );         # Write out updated entry
}

print "\nSaving results to file ($bib_outfile).\n\n"; 
move( $bib_tempfile, $bib_outfile ) or die("Copy failed: $!"); 