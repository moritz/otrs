# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentStatistics;

use strict;
use warnings;

use List::Util qw( first );

#use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

# TODO remove after notification merge in master
sub Translatable {
    return shift;
}

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    for my $NeededData (qw( UserID Subaction AccessRo SessionID ))
    {
        if ( !$Param{$NeededData} ) {
            $Kernel::OM->Get('Kernel::Output::HTML::Layout')->FatalError( Message => "Got no $NeededData!" );
        }
        $Self->{$NeededData} = $Param{$NeededData};
    }

    # AccessRw controls the adding/editing of statistics.
    for my $Param (qw( AccessRw RequestedURL)) {
        if ( $Param{$Param} ) {
            $Self->{$Param} = $Param{$Param};
        }
    }

    # create stats object
    $Kernel::OM->ObjectParamAdd(
        'Kernel::System::Stats' => {
            UserID => $Param{UserID},
        },
    );
    $Self->{StatsObject} = $Kernel::OM->Get('Kernel::System::Stats');

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    if ( $Self->{Subaction} eq 'Overview' ) {
        return $Self->OverviewScreen();
    }
    elsif ( $Self->{Subaction} eq 'Import' ) {
        return $Self->ImportScreen();
    }
    elsif ( $Self->{Subaction} eq 'Export' ) {
        return $Self->ExportAction();
    }

    # No (known) subaction?
    return $Kernel::OM->Get('Kernel::Output::HTML::Layout')->ErrorScreen( Message => 'Invalid Subaction.' );
}

sub OverviewScreen {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # permission check
    $Self->{AccessRo} || return $LayoutObject->NoPermission( WithHeader => 'yes' );

    # Get Params
    $Param{SearchPageShown} = $ConfigObject->Get('Stats::SearchPageShown') || 10;
    $Param{SearchLimit}     = $ConfigObject->Get('Stats::SearchLimit')     || 100;
    $Param{OrderBy}   = $ParamObject->GetParam( Param => 'OrderBy' )   || 'ID';
    $Param{Direction} = $ParamObject->GetParam( Param => 'Direction' ) || 'ASC';
    $Param{StartHit} = int( $ParamObject->GetParam( Param => 'StartHit' ) || 1 );

    # store last screen
    $Kernel::OM->Get('Kernel::System::AuthSession')->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastStatsOverview',
        Value     => $Self->{RequestedURL},
        StoreData => 1,
    );

    # get all Stats from the db
    my $Result = $Self->{StatsObject}->GetStatsList(
        AccessRw  => $Self->{AccessRw},
        OrderBy   => $Param{OrderBy},
        Direction => $Param{Direction},
    );

    my %Order2CSSSort = (
        ASC  => 'SortAscending',
        DESC => 'SortDescending',
    );

    my %InverseSorting = (
        ASC  => 'DESC',
        DESC => 'ASC',
    );

    $Param{ 'CSSSort' . $Param{OrderBy} } = $Order2CSSSort{ $Param{Direction} };
    for my $Type (qw(ID Title Object)) {
        $Param{"LinkSort$Type"} = ( $Param{OrderBy} eq $Type ) ? $InverseSorting{ $Param{Direction} } : 'ASC';
    }

    # build the info
    my %Pagination = $LayoutObject->PageNavBar(
        Limit     => $Param{SearchLimit},
        StartHit  => $Param{StartHit},
        PageShown => $Param{SearchPageShown},
        AllHits   => $#{$Result} + 1,
        Action    => 'Action=AgentStatistics;Subaction=Overview',
        Link      => ";Direction=$Param{Direction};OrderBy=$Param{OrderBy};",
        IDPrefix  => 'AgentStatisticsOverview'
    );

    # list result
    my $Index = -1;
    for ( my $Z = 0; ( $Z < $Param{SearchPageShown} && $Index < $#{$Result} ); $Z++ ) {
        $Index = $Param{StartHit} + $Z - 1;
        my $StatID = $Result->[$Index];
        my $Stat   = $Self->{StatsObject}->StatsGet(
            StatID             => $StatID,
            NoObjectAttributes => 1,
        );

        # get the object name
        if ( $Stat->{StatType} eq 'static' ) {
            $Stat->{ObjectName} = $Stat->{File};
        }

        # if no object name is defined use an empty string
        $Stat->{ObjectName} ||= '';

        $LayoutObject->Block(
            Name => 'Result',
            Data => {
                %$Stat,
                AccessRw => $Self->{AccessRw},
            },
        );
    }

    # build output
    my $Output = $LayoutObject->Header( Title => 'Overview' );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        Data => {
            %Pagination,
            %Param,
            AccessRw => $Self->{AccessRw},
        },
        TemplateFile => 'AgentStatisticsOverview',
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

sub ImportScreen {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');

    if (!$Self->{AccessRw}) {
        return $LayoutObject->NoPermission( WithHeader => 'yes' )
    }

    my %Error;
    my $Status = $ParamObject->GetParam( Param => 'Status' );

    if ( $Status && $Status eq 'Action' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my $UploadFile = $ParamObject->GetParam( Param => 'File' );
        if ($UploadFile) {
            my %UploadStuff = $ParamObject->GetUploadAll(
                Param    => 'File',
                Encoding => 'Raw'
            );
            if ( $UploadStuff{Content} =~ m{<otrs_stats>}x ) {
                my $StatID = $Self->{StatsObject}->Import(
                    Content => $UploadStuff{Content},
                );

                if ($StatID) {
                    $Error{FileServerError}        = 'ServerError';
                    $Error{FileServerErrorMessage} = Translatable("Statistic could not be imported.");
                }

                # redirect to configure
                return $LayoutObject->Redirect(
                    OP => "Action=AgentStatistics;Subaction=Edit;StatID=$StatID"
                );
            }
            else {
                $Error{FileServerError}        = 'ServerError';
                $Error{FileServerErrorMessage} = Translatable("Please upload a valid statistic file.");
            }
        }
        else {
            $Error{FileServerError}        = 'ServerError';
            $Error{FileServerErrorMessage} = Translatable("This field is required.");
        }
    }

    my $Output = $LayoutObject->Header( Title => 'Import' );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatisticsImport',
        Data         => {
            %Error,
        },
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

sub ExportAction {
    my ($Self, %Param) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    if (!$Self->{AccessRw}) {
        return $LayoutObject->NoPermission( WithHeader => 'yes' );
    }

    my $StatID = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'StatID' );
    if ( !$StatID ) {
        return $LayoutObject->ErrorScreen( Message => 'Export: Need StatID!' );
    }

    my $ExportFile = $Self->{StatsObject}->Export( StatID => $StatID );

    return $LayoutObject->Attachment(
        Filename    => $ExportFile->{Filename},
        Content     => $ExportFile->{Content},
        ContentType => 'text/xml',
    );
}

1;
