#!/usr/local/bin/perl
# 
#   small tool to format or convert DJI-FPV-SRT files
#
#   usage: convertSRT.pl <input-file> [<output-file>]
#
use warnings;


use constant OUTPUTFORMAT => ASS;           # ASS or CSV
use constant ALIGN      => 9;               # 3 right bottom, 9 right top, see ASS format for details
use constant MARGIN     => 3;               # distance to the border 0, 10 or whatever

use constant FONTSIZE           => 13;          # 10, 15 or whatever
use constant FONTTRANSPARENCY   => 0;           # 0 to 255
use constant FONTCOLOR          => q(FFFFFF);   # 0 to 255

use constant BITRATE_BAR_ENABLE  => 1;          # 0 disable, 1 enable-full,  dont use with mode CSV!
use constant BITRATE_BAR_SIZEPCT => 50;         # size in percent related to font size and charachter
use constant BITRATE_BAR_CHAR    => '▄';        # or █
#use constant BITRATE_BAR_COLORS  => qw(H959595 HFFFFFF);  # white on grey
use constant BITRATE_BAR_COLORS => qw(H959595  H0000FF H0079FF H3BFF00 );  # grey, red, orange, green

use constant OUTPUTTEMPLATE     => q(Dialogue: 0,{start_time},{end_time},Default,,0,0,0,,{bitrate}\N{delay}); # example subtitles
use constant OUTPUTTEMPLATECSV  => q({end_time},{signal},{ch},{flightTime},{uavBat},{glsBat},{uavBatCells},{glsBatCells},{delay},{bitrate},{rcSignal}); #example CSV

### available fields:
# {signal}
# {ch}
# {flightTime}
# {uavBat}
# {glsBat}
# {uavBatCells}
# {glsBatCells}
# {delay}
# {bitrate}
# {rcSignal}
# {start_time}
# {end_time}
###



my $header = q([Script Info]
Title: Default file
ScriptType: v4.00+
WrapStyle: 0
ScaledBorderAndShadow: yes
YCbCr Matrix: None

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Consolas,).FONTSIZE.q(,&H).sprintf("%X%s", FONTTRANSPARENCY,FONTCOLOR).q(,&H).sprintf("%X", FONTTRANSPARENCY).q(0000FF,&H7E000000,&HFF000000,0,0,0,0,100,100,0,0,1,1,0,).ALIGN.q(,).MARGIN.q(,).MARGIN.q(,).MARGIN.q(,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
);

# more examples for Style:
#Style: Default,Arial,13,&H00FFFFFF,&H000000FF,&H7E000000,&HFF000000,0,0,0,0,100,100,0,0,1,1,0,3,10,10,10,1
#Style: Default,Consolas,13,&H00FFFFFF,&H000000FF,&H7E000000,&HFF000000,0,0,0,0,80,100,0,0,1,1,0,3,10,10,10,1


# begin of the script #

    my $version = "v0.0.2";
    my $inputFile  = $ARGV[0];
    my $outputFile = $ARGV[1];
       $outputFile = $inputFile =~ s/\.srt/\.csv/gr if !$outputFile && OUTPUTFORMAT eq 'CSV'; 
       $outputFile = $inputFile =~ s/\.srt/\.ass/gr if !$outputFile; 
    my $maxBitrate;
    my $bitrateBarCharacter = BITRATE_BAR_CHAR;
    my @bitrateBarColor     = BITRATE_BAR_COLORS; 

    print "| DJI SRT converter, $version\n";
    die "!! could not open file $inputFile\n" if ! -e $inputFile ;
    print "| converting $inputFile to $outputFile \n";
    my $outputTemplate = OUTPUTTEMPLATE =~ s/\n|\r|\n\r//gr;
       $outputTemplate = OUTPUTTEMPLATECSV =~ s/\n|\r|\n\r//gr if OUTPUTFORMAT eq 'CSV'; 

    my @fields = qw(
        signal:(\d+)
        ch:(\d+)
        flightTime:(.+)
        uavBat:([0-9\.]+V)
        glsBat:([0-9\.]+V)
        uavBatCells:(\d+)
        glsBatCells:(\d+)
        delay:(\d+ms)
        bitrate:(\d+\.\d+Mbps)
        rcSignal:(\d+)
    );

    open FI, $inputFile;
    open FO, "> $outputFile";
    print FO $header if OUTPUTFORMAT ne 'CSV'; 
    print FO ($outputTemplate =~ s/{|}//gr )."\n" if OUTPUTFORMAT eq 'CSV'; 

    while (my $line = <FI>){
        chomp($line);

        if($line =~ m/^\d+$/){
            my $time = <FI>;            #00:00:00,050 --> 00:00:00,150
            $time =~ s/,/./g;           #00:00:00.050 --> 00:00:00.150

            my $dataMap;
            ( $dataMap->{'start_time'}, $dataMap->{'end_time'} ) = $time =~ m/0(.+)\d --> 0(.+)\d/;

            my $rawData = <FI>;         #signal:4 ch:2 flightTime:1 uavBat:14.8V glsBat:15.3V uavBatCells:4 glsBatCells:4 delay:39ms bitrate:50.8Mbps rcSignal:0
            chomp($rawData);

            my $rgx = join (" ", map { $_ }  @fields );             # build regex to match values
            $rgx =~ s/\+\w*\)/\+\)\.\*/g if OUTPUTFORMAT eq 'CSV';      # remove all strings for csv export
            my @vars =  map { $_ =~ m/(.+):.+/ } @fields ;          # extract var names
            my @data = $rawData =~ m/$rgx/;                         # execute regex
            map { $dataMap->{ $vars[$_] } = $data[$_] } 0..$#data;  # populate var->values
            my $output = $outputTemplate;                           # reset template

            if( BITRATE_BAR_ENABLE ){
                my ( $bitrate) = $dataMap->{'bitrate'} =~ m/(\d.+)\..+Mbps/;
                $bitrate = int($bitrate/100*BITRATE_BAR_SIZEPCT);

                $maxBitrate = int($bitrate) if !$maxBitrate;
                my $bitrateBar;
                my $i=$maxBitrate;
                while($i > 0){
                    my $colorIndex=0;                            # set color to background
                    if($bitrate < $i){                           # counter is below bitrate, background color
                        $colorIndex=0;                           # set color to background
                    }else{                                       # calculate color codings
                        $colorIndex = int((scalar(@bitrateBarColor-1) * ($bitrate / $maxBitrate ) )+0.6);
                    }
                    $bitrateBar .=  sprintf('{\c&%s&}%s', $bitrateBarColor[$colorIndex] ? $bitrateBarColor[$colorIndex] : $bitrateBarColor[1] , $bitrateBarCharacter ); 
                    $i--;
                }
                $bitrateBar .= sprintf('{\c&%X%s}', FONTTRANSPARENCY,FONTCOLOR);     #reset color
                $output =~ s/\{bitrate\}/$bitrateBar/;          # replace in output string
            }

            map { $output =~ s/\{$_\}/$dataMap->{$_}/ } ($outputTemplate =~ m/\{([^\}]+)\}/g); # replace all variables in output string
            print FO "$output\n";                                      # write line
        }
    }

    close FI;
    close FO;
    print "| done.\n";
    exit 0;