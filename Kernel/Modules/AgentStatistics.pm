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

use Kernel::System::VariableCheck qw(:all);

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

    # Create stats object (requires UserID).
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
    elsif ( $Self->{Subaction} eq 'Delete' ) {
        return $Self->DeleteAction();
    }
    elsif ( $Self->{Subaction} eq 'Edit' ) {
        return $Self->EditScreen();
    }
    elsif ( $Self->{Subaction} eq 'View' ) {
        return $Self->ViewScreen();
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

    if ( !$Self->{AccessRw} ) {
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
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    if ( !$Self->{AccessRw} ) {
        return $LayoutObject->NoPermission( WithHeader => 'yes' );
    }

    $LayoutObject->ChallengeTokenCheck();

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

sub DeleteAction {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');

    if ( !$Self->{AccessRw} ) {
        return $LayoutObject->NoPermission( WithHeader => 'yes' );
    }

    my $StatID = $ParamObject->GetParam( Param => 'StatID' );
    if ( !$StatID ) {
        return $LayoutObject->ErrorScreen( Message => 'Delete: Get no StatID!' );
    }

    # challenge token check for write action
    $LayoutObject->ChallengeTokenCheck();
    $Self->{StatsObject}->StatsDelete( StatID => $StatID );
    return $LayoutObject->Redirect( OP => 'Action=AgentStatistics;Subaction=Overview' );
}

sub EditScreen {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # permission check
    return $LayoutObject->NoPermission( WithHeader => 'yes' ) if !$Self->{AccessRw};

    # get param
    if ( !( $Param{StatID} = $ParamObject->GetParam( Param => 'StatID' ) ) ) {
        return $LayoutObject->ErrorScreen(
            Message => 'EditSpecification: Need StatID!',
        );
    }

    my $Stat = $Self->{StatsObject}->StatsGet( StatID => $Param{StatID} );

    my %Frontend;
    $Frontend{GeneralSpecificationsWidget} = $Self->_GeneralSpecificationsWidget(
        StatID => $Stat->{StatID},
    );

    my $Output = $LayoutObject->Header( Title => 'Edit' );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatisticsEdit',
        Data         => {
            %Frontend,
            %{$Stat},
        },
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

sub ViewScreen {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # permission check
    $Self->{AccessRo} || return $LayoutObject->NoPermission( WithHeader => 'yes' );

    # get StatID
    my $StatID = $ParamObject->GetParam( Param => 'StatID' );
    if ( !$StatID ) {
        return $LayoutObject->ErrorScreen( Message => 'Need StatID!' );
    }

    # get message if one available
    #my $Message = $ParamObject->GetParam( Param => 'Message' );

    # Get all statistics that the current user may see (does permission check).
    my $StatsList = $Self->{StatsObject}->StatsListGet();

    my $Stat = $StatsList->{$StatID};

    # get param
    if ( !IsHashRefWithData($Stat) ) {
        return $LayoutObject->ErrorScreen(
            Message => 'Could not load stat.',
        );
    }

    my $Output = $LayoutObject->Header( Title => 'View' );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatisticsView',
        Data         => {
            #%Frontend,
            #%{$Stat},
        },
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

sub _GeneralSpecificationsWidget {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $Stat;
    if ( $Param{StatID} ) {
        $Stat = $Self->{StatsObject}->StatsGet( StatID => $Param{StatID} );
    }
    else {
        $Stat->{StatID}     = 'new';
        $Stat->{StatNumber} = '';
        $Stat->{Valid}      = 1;
    }

    my %Frontend;

    # create selectboxes 'Cache', 'SumRow', 'SumCol', and 'Valid'
    for my $Key (qw(Cache ShowAsDashboardWidget SumRow SumCol)) {
        $Frontend{ 'Select' . $Key } = $LayoutObject->BuildSelection(
            Data => {
                0 => 'No',
                1 => 'Yes'
            },
            SelectedID => $Stat->{$Key} || 0,
            Name => $Key,
        );
    }

    # If this is a new stat, assume that it does not support the dashboard widget at the start.
    #   This is corrected by a call to AJAXUpdate when the page loads and when the user makes changes.
    if ( $Stat->{StatID} eq 'new' || !$Stat->{ObjectBehaviours}->{ProvidesDashboardWidget} ) {
        $Frontend{'SelectShowAsDashboardWidget'} = $LayoutObject->BuildSelection(
            Data => {
                0 => 'No (not supported)',
            },
            SelectedID => 0,
            Name       => 'ShowAsDashboardWidget',
        );
    }

    $Frontend{SelectValid} = $LayoutObject->BuildSelection(
        Data => {
            0 => 'invalid',
            1 => 'valid',
        },
        SelectedID => $Stat->{Valid},
        Name       => 'Valid',
    );

    # create multiselectboxes 'permission'
    my %Permission = (
        Data        => { $Kernel::OM->Get('Kernel::System::Group')->GroupList( Valid => 1 ) },
        Name        => 'Permission',
        Class       => 'Validate_Required',
        Multiple    => 1,
        Size        => 5,
        Translation => 0,
    );
    if ( $Stat->{Permission} ) {
        $Permission{SelectedID} = $Stat->{Permission};
    }
    else {
        $Permission{SelectedValue} = $ConfigObject->Get('Stats::DefaultSelectedPermissions');
    }
    $Stat->{SelectPermission} = $LayoutObject->BuildSelection(%Permission);

    # create multiselectboxes 'format'
    my $GDAvailable;
    my $AvailableFormats = $ConfigObject->Get('Stats::Format');

    # check availability of packages
    for my $Module ( 'GD', 'GD::Graph' ) {
        $GDAvailable = ( $Kernel::OM->Get('Kernel::System::Main')->Require($Module) ) ? 1 : 0;
    }

    # if the GD package is not installed, all the graph options will be disabled
    if ( !$GDAvailable ) {
        my @FormatData = map {
            Key          => $_,
                Value    => $AvailableFormats->{$_},
                Disabled => ( ( $_ =~ m/GD/gi ) ? 1 : 0 ),
        }, keys %{$AvailableFormats};

        $AvailableFormats = \@FormatData;
        $LayoutObject->Block( Name => 'PackageUnavailableMsg' );
    }

    $Stat->{SelectFormat} = $LayoutObject->BuildSelection(
        Data       => $AvailableFormats,
        Name       => 'Format',
        Class      => 'Validate_Required',
        Multiple   => 1,
        Size       => 5,
        SelectedID => $Stat->{Format}
            || $ConfigObject->Get('Stats::DefaultSelectedFormat'),
    );

    # create multiselectboxes 'graphsize'
    $Stat->{SelectGraphSize} = $LayoutObject->BuildSelection(
        Data        => $ConfigObject->Get('Stats::GraphSize'),
        Name        => 'GraphSize',
        Multiple    => 1,
        Size        => 3,
        SelectedID  => $Stat->{GraphSize},
        Translation => 0,
        Disabled    => ( first { $_ =~ m{^GD::}smx } @{ $Stat->{GraphSize} } ) ? 0 : 1,
    );

    my $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatistics/GeneralSpecificationsWidget',
        Data         => {
            %Frontend,
            %{$Stat},
        },
    );
    return $Output;
}

1;
