# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::Statistics::View;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Log',
    'Kernel::System::PDF',
    'Kernel::System::Stats',
    'Kernel::System::Ticket',
    'Kernel::System::User',
    'Kernel::System::Web::Request',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{StatsObject} = $Param{StatsObject} || die 'Need StatsObject!';

    return $Self;
}

sub StatsViewParameterWidget {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # check if need params are available
    for my $Needed (qw(Stat)) {
        if ( !$Param{$Needed} ) {
            return $LayoutObject->ErrorScreen( Message => "Need $Needed!" );
        }
    }

    my $Stat   = $Param{Stat};
    my $StatID = $Stat->{StatID};

    my $Output;

    # get the object name
    if ( $Stat->{StatType} eq 'static' ) {
        $Stat->{ObjectName} = $Stat->{File};
    }

    # if no object name is defined use an empty string
    $Stat->{ObjectName} ||= '';

    $Stat->{Description} = $LayoutObject->Ascii2Html(
        Text           => $Stat->{Description},
        HTMLResultMode => 1,
        NewLine        => 72,
    );

    # create format select box
    my %SelectFormat;
    my $Flag    = 0;
    my $Counter = 0;
    my $Format  = $ConfigObject->Get('Stats::Format');
    for my $UseAsValueSeries ( @{ $Stat->{UseAsValueSeries} } ) {
        if ( $UseAsValueSeries->{Selected} ) {
            $Counter++;
        }
    }
    my $CounterII = 0;
    for my $Value ( @{ $Stat->{Format} } ) {
        if ( $Counter == 0 || $Value ne 'GD::Graph::pie' ) {
            $SelectFormat{$Value} = $Format->{$Value};
            $CounterII++;
        }
        if ( $Value =~ m{^GD::Graph\.*}x ) {
            $Flag = 1;
        }
    }
    if ( $CounterII > 1 ) {
        my %Frontend;
        $Frontend{SelectFormat} = $LayoutObject->BuildSelection(
            Data => \%SelectFormat,
            Name => 'Format',
        );
        $LayoutObject->Block(
            Name => 'Format',
            Data => \%Frontend,
        );
    }
    else {
        $LayoutObject->Block(
            Name => 'FormatFixed',
            Data => {
                Format    => $Format->{ $Stat->{Format}->[0] },
                FormatKey => $Stat->{Format}->[0],
            },
        );
    }

    # create graphic size select box
    if ( $Stat->{GraphSize} && $Flag ) {
        my %GraphSize;
        my %Frontend;
        my $GraphSizeRef = $ConfigObject->Get('Stats::GraphSize');
        for my $Value ( @{ $Stat->{GraphSize} } ) {
            $GraphSize{$Value} = $GraphSizeRef->{$Value};
        }
        if ( $#{ $Stat->{GraphSize} } > 0 ) {
            $Frontend{SelectGraphSize} = $LayoutObject->BuildSelection(
                Data        => \%GraphSize,
                Name        => 'GraphSize',
                Translation => 0,
            );
            $LayoutObject->Block(
                Name => 'Graphsize',
                Data => \%Frontend,
            );
        }
        else {
            $LayoutObject->Block(
                Name => 'GraphsizeFixed',
                Data => {
                    GraphSize    => $GraphSizeRef->{ $Stat->{GraphSize}->[0] },
                    GraphSizeKey => $Stat->{GraphSize}->[0],
                },
            );
        }
    }

    if ( $ConfigObject->Get('Stats::ExchangeAxis') ) {
        my $ExchangeAxis = $LayoutObject->BuildSelection(
            Data => {
                1 => 'Yes',
                0 => 'No'
            },
            Name       => 'ExchangeAxis',
            SelectedID => 0,
        );

        $LayoutObject->Block(
            Name => 'ExchangeAxis',
            Data => { ExchangeAxis => $ExchangeAxis }
        );
    }

    # get static attributes
    if ( $Stat->{StatType} eq 'static' ) {

        # load static module
        my $Params = $Self->{StatsObject}->GetParams( StatID => $StatID );
        $LayoutObject->Block(
            Name => 'Static',
        );
        PARAMITEM:
        for my $ParamItem ( @{$Params} ) {
            next PARAMITEM if $ParamItem->{Name} eq 'GraphSize';
            $LayoutObject->Block(
                Name => 'ItemParam',
                Data => {
                    Param => $ParamItem->{Frontend},
                    Name  => $ParamItem->{Name},
                    Field => $LayoutObject->BuildSelection(
                        Data       => $ParamItem->{Data},
                        Name       => $ParamItem->{Name},
                        SelectedID => $ParamItem->{SelectedID} || '',
                        Multiple   => $ParamItem->{Multiple} || 0,
                        Size       => $ParamItem->{Size} || '',
                    ),
                },
            );
        }
    }

    # get dynamic attributes
    elsif ( $Stat->{StatType} eq 'dynamic' ) {
        my %Name = (
            UseAsXvalue      => 'X-axis',
            UseAsValueSeries => 'Value Series',
            UseAsRestriction => 'Restrictions',
        );

        for my $Use (qw(UseAsXvalue UseAsValueSeries UseAsRestriction)) {
            my $Flag = 0;
            $LayoutObject->Block(
                Name => 'Dynamic',
                Data => { Name => $Name{$Use} },
            );
            OBJECTATTRIBUTE:
            for my $ObjectAttribute ( @{ $Stat->{$Use} } ) {
                next OBJECTATTRIBUTE if !$ObjectAttribute->{Selected};

                my %ValueHash;
                $Flag = 1;

                # Select All function
                if ( !$ObjectAttribute->{SelectedValues}[0] ) {
                    if (
                        $ObjectAttribute->{Values} && ref $ObjectAttribute->{Values} ne 'HASH'
                        )
                    {
                        $Kernel::OM->Get('Kernel::System::Log')->Log(
                            Priority => 'error',
                            Message  => 'Values needs to be a hash reference!'
                        );
                        next OBJECTATTRIBUTE;
                    }
                    my @Values = keys( %{ $ObjectAttribute->{Values} } );
                    $ObjectAttribute->{SelectedValues} = \@Values;
                }
                for ( @{ $ObjectAttribute->{SelectedValues} } ) {
                    if ( $ObjectAttribute->{Values} ) {
                        $ValueHash{$_} = $ObjectAttribute->{Values}{$_};
                    }
                    else {
                        $ValueHash{Value} = $_;
                    }
                }

                $LayoutObject->Block(
                    Name => 'Element',
                    Data => { Name => $ObjectAttribute->{Name} },
                );

                # show fixed elements
                if ( $ObjectAttribute->{Fixed} ) {
                    if ( $ObjectAttribute->{Block} eq 'Time' ) {
                        if ( $Use eq 'UseAsRestriction' ) {
                            delete $ObjectAttribute->{SelectedValues};
                        }
                        my $TimeScale = _TimeScale();
                        if ( $ObjectAttribute->{TimeStart} ) {
                            $LayoutObject->Block(
                                Name => 'TimePeriodFixed',
                                Data => {
                                    TimeStart => $ObjectAttribute->{TimeStart},
                                    TimeStop  => $ObjectAttribute->{TimeStop},
                                },
                            );
                        }
                        elsif ( $ObjectAttribute->{TimeRelativeUnit} ) {
                            $LayoutObject->Block(
                                Name => 'TimeRelativeFixed',
                                Data => {
                                    TimeRelativeUnit =>
                                        $TimeScale->{ $ObjectAttribute->{TimeRelativeUnit} }
                                        {Value},
                                    TimeRelativeCount => $ObjectAttribute->{TimeRelativeCount},
                                },
                            );
                        }
                        if ( $ObjectAttribute->{SelectedValues}[0] ) {
                            $LayoutObject->Block(
                                Name => 'TimeScaleFixed',
                                Data => {
                                    Scale =>
                                        $TimeScale->{ $ObjectAttribute->{SelectedValues}[0] }
                                        {Value},
                                    Count => $ObjectAttribute->{TimeScaleCount},
                                },
                            );
                        }
                    }
                    else {

                        # find out which sort mechanism is used
                        my @Sorted;
                        if ( $ObjectAttribute->{SortIndividual} ) {
                            @Sorted = grep { $ValueHash{$_} }
                                @{ $ObjectAttribute->{SortIndividual} };
                        }
                        else {
                            @Sorted = sort { $ValueHash{$a} cmp $ValueHash{$b} } keys %ValueHash;
                        }

                        for (@Sorted) {
                            my $Value = $ValueHash{$_};
                            if ( $ObjectAttribute->{Translation} ) {
                                $Value = $LayoutObject->{LanguageObject}->Translate( $ValueHash{$_} );
                            }
                            $LayoutObject->Block(
                                Name => 'Fixed',
                                Data => {
                                    Value   => $Value,
                                    Key     => $_,
                                    Use     => $Use,
                                    Element => $ObjectAttribute->{Element},
                                },
                            );
                        }
                    }
                }

                # show  unfixed elements
                else {
                    my %BlockData;
                    $BlockData{Name}    = $ObjectAttribute->{Name};
                    $BlockData{Element} = $ObjectAttribute->{Element};
                    $BlockData{Value}   = $ObjectAttribute->{SelectedValues}->[0];

                    if ( $ObjectAttribute->{Block} eq 'MultiSelectField' ) {
                        $BlockData{SelectField} = $LayoutObject->BuildSelection(
                            Data           => \%ValueHash,
                            Name           => $Use . $ObjectAttribute->{Element},
                            Multiple       => 1,
                            Size           => 5,
                            SelectedID     => $ObjectAttribute->{SelectedValues},
                            Translation    => $ObjectAttribute->{Translation},
                            TreeView       => $ObjectAttribute->{TreeView} || 0,
                            Sort           => $ObjectAttribute->{Sort} || undef,
                            SortIndividual => $ObjectAttribute->{SortIndividual} || undef,
                        );
                        $LayoutObject->Block(
                            Name => 'MultiSelectField',
                            Data => \%BlockData,
                        );
                    }
                    elsif ( $ObjectAttribute->{Block} eq 'SelectField' ) {

                        $BlockData{SelectField} = $LayoutObject->BuildSelection(
                            Data           => \%ValueHash,
                            Name           => $Use . $ObjectAttribute->{Element},
                            Translation    => $ObjectAttribute->{Translation},
                            TreeView       => $ObjectAttribute->{TreeView} || 0,
                            Sort           => $ObjectAttribute->{Sort} || undef,
                            SortIndividual => $ObjectAttribute->{SortIndividual} || undef,
                        );
                        $LayoutObject->Block(
                            Name => 'SelectField',
                            Data => \%BlockData,
                        );
                    }

                    elsif ( $ObjectAttribute->{Block} eq 'InputField' ) {
                        $LayoutObject->Block(
                            Name => 'InputField',
                            Data => {
                                Key   => $Use . $ObjectAttribute->{Element},
                                Value => $ObjectAttribute->{SelectedValues}[0],
                            },
                        );
                    }
                    elsif ( $ObjectAttribute->{Block} eq 'Time' ) {
                        $ObjectAttribute->{Element} = $Use . $ObjectAttribute->{Element};
                        my $TimeType = $ConfigObject->Get('Stats::TimeType')
                            || 'Normal';
                        my %TimeData = _Timeoutput(
                            $Self, %{$ObjectAttribute},
                            OnlySelectedAttributes => 1
                        );
                        %BlockData = ( %BlockData, %TimeData );
                        if ( $ObjectAttribute->{TimeStart} ) {
                            $BlockData{TimeStartMax} = $ObjectAttribute->{TimeStart};
                            $BlockData{TimeStopMax}  = $ObjectAttribute->{TimeStop};
                            $LayoutObject->Block(
                                Name => 'TimePeriod',
                                Data => \%BlockData,
                            );
                        }

                        elsif ( $ObjectAttribute->{TimeRelativeUnit} ) {
                            my $TimeScale = _TimeScale();
                            if ( $TimeType eq 'Extended' ) {
                                my %TimeScaleOption;
                                ITEM:
                                for (
                                    sort {
                                        $TimeScale->{$a}->{Position}
                                            <=> $TimeScale->{$b}->{Position}
                                    } keys %{$TimeScale}
                                    )
                                {
                                    $TimeScaleOption{$_} = $TimeScale->{$_}{Value};
                                    last ITEM if $ObjectAttribute->{TimeRelativeUnit} eq $_;
                                }
                                $BlockData{TimeRelativeUnit} = $LayoutObject->BuildSelection(
                                    Name           => $ObjectAttribute->{Element} . 'TimeRelativeUnit',
                                    Data           => \%TimeScaleOption,
                                    Sort           => 'IndividualKey',
                                    SelectedID     => $ObjectAttribute->{TimeRelativeUnit},
                                    SortIndividual => [
                                        'Second', 'Minute', 'Hour', 'Day',
                                        'Week', 'Month', 'Year'
                                    ],
                                );
                            }
                            $BlockData{TimeRelativeCountMax} = $ObjectAttribute->{TimeRelativeCount};
                            $BlockData{TimeRelativeUnitMax}
                                = $TimeScale->{ $ObjectAttribute->{TimeRelativeUnit} }{Value};

                            $LayoutObject->Block(
                                Name => 'TimePeriodRelative',
                                Data => \%BlockData,
                            );
                        }

                        # build the Timescale output
                        if ( $Use ne 'UseAsRestriction' ) {
                            if ( $TimeType eq 'Normal' ) {
                                $BlockData{TimeScaleCount} = 1;
                                $BlockData{TimeScaleUnit}  = $BlockData{TimeSelectField};
                            }
                            elsif ( $TimeType eq 'Extended' ) {
                                my $TimeScale = _TimeScale();
                                my %TimeScaleOption;
                                ITEM:
                                for (
                                    sort {
                                        $TimeScale->{$b}->{Position}
                                            <=> $TimeScale->{$a}->{Position}
                                    } keys %{$TimeScale}
                                    )
                                {
                                    $TimeScaleOption{$_} = $TimeScale->{$_}->{Value};
                                    last ITEM if $ObjectAttribute->{SelectedValues}[0] eq $_;
                                }
                                $BlockData{TimeScaleUnitMax} = $TimeScale->{ $ObjectAttribute->{SelectedValues}[0] }
                                    {Value};
                                $BlockData{TimeScaleCountMax} = $ObjectAttribute->{TimeScaleCount};

                                $BlockData{TimeScaleUnit} = $LayoutObject->BuildSelection(
                                    Name           => $ObjectAttribute->{Element},
                                    Data           => \%TimeScaleOption,
                                    SelectedID     => $ObjectAttribute->{SelectedValues}[0],
                                    Sort           => 'IndividualKey',
                                    SortIndividual => [
                                        'Second', 'Minute', 'Hour', 'Day',
                                        'Week', 'Month', 'Year'
                                    ],
                                );
                                $LayoutObject->Block(
                                    Name => 'TimeScaleInfo',
                                    Data => \%BlockData,
                                );
                            }
                            if ( $ObjectAttribute->{SelectedValues} ) {
                                $LayoutObject->Block(
                                    Name => 'TimeScale',
                                    Data => \%BlockData,
                                );
                                if ( $BlockData{TimeScaleUnitMax} ) {
                                    $LayoutObject->Block(
                                        Name => 'TimeScaleInfo',
                                        Data => \%BlockData,
                                    );
                                }
                            }
                        }

                        # end of build timescale output
                    }
                }
            }

            # Show this Block if no value series or restrictions are selected
            if ( !$Flag ) {
                $LayoutObject->Block(
                    Name => 'NoElement',
                );
            }
        }
    }
    my %YesNo = (
        0 => 'No',
        1 => 'Yes'
    );
    my %ValidInvalid = (
        0 => 'invalid',
        1 => 'valid'
    );
    $Stat->{SumRowValue}                = $YesNo{ $Stat->{SumRow} };
    $Stat->{SumColValue}                = $YesNo{ $Stat->{SumCol} };
    $Stat->{CacheValue}                 = $YesNo{ $Stat->{Cache} };
    $Stat->{ShowAsDashboardWidgetValue} = $YesNo{ $Stat->{ShowAsDashboardWidget} // 0 };
    $Stat->{ValidValue}                 = $ValidInvalid{ $Stat->{Valid} };

    for (qw(CreatedBy ChangedBy)) {
        $Stat->{$_} = $Kernel::OM->Get('Kernel::System::User')->UserName( UserID => $Stat->{$_} );
    }

    # # store last screen
    # $SessionObject->UpdateSessionID(
    #     SessionID => $Self->{SessionID},
    #     Key       => 'LastStatsView',
    #     Value     => $Self->{RequestedURL},
    # );

    # Completeness check
    my @Notify = $Self->{StatsObject}->CompletenessCheck(
        StatData => $Stat,
        Section  => 'All'
    );

    # show the start button if the stat is valid and completeness check true
    if ( $Stat->{Valid} && !@Notify ) {
        $LayoutObject->Block(
            Name => 'FormSubmit',
            Data => $Stat,
        );
    }

    # check if the PDF module is installed and enabled
    if ( $ConfigObject->Get('PDF') ) {
        $Stat->{PDFUsable} = $Kernel::OM->Get('Kernel::System::PDF') ? 1 : 0;
    }

    # Error message if there is an invalid setting in the search mask
    # in need of better solution

    my $Message = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'Message' );

    if ($Message) {
        my %ErrorMessages = (
            1 => 'The selected start time is before the allowed start time!',
            2 => 'The selected end time is later than the allowed end time!',
            3 => 'The selected time period is larger than the allowed time period!',
            4 => 'Your reporting time interval is too small, please use a larger time scale!',
        );

        $Output .= $LayoutObject->Notify(
            Info     => $ErrorMessages{$Message},
            Priority => 'Error',
        );
    }

    # Show warning if restrictions contain stop words within ticket search.
    if (
        $Stat->{UseAsRestriction}
        && ref $Stat->{UseAsRestriction} eq 'ARRAY'
        && $Kernel::OM->Get('Kernel::System::Ticket')->SearchStringStopWordsUsageWarningActive()
        )
    {
        my %StopWordFields = $Self->_StopWordFieldsGet();
        my %StopWordStrings;

        RESTRICTION:
        for my $Restriction ( @{ $Stat->{UseAsRestriction} } ) {
            next RESTRICTION if !$Restriction->{Name};
            next RESTRICTION if !$StopWordFields{ $Restriction->{Name} };
            next RESTRICTION if !$Restriction->{SelectedValues};
            next RESTRICTION if ref $Restriction->{SelectedValues} ne 'ARRAY';

            for my $StopWordString ( @{ $Restriction->{SelectedValues} } ) {
                $StopWordStrings{ $Restriction->{Name} } = $StopWordString;
            }
        }

        if (%StopWordStrings) {
            my %StopWordsServerErrors = $Self->_StopWordsServerErrorsGet(%StopWordStrings);
            if (%StopWordsServerErrors) {
                my $Info = $LayoutObject->{LanguageObject}->Translate(
                    'Please check restrictions of this stat for errors.'
                );

                $Output .= $LayoutObject->Notify(
                    Info     => $Info,
                    Priority => 'Error',
                );
            }
        }
    }

    $Output .= $Self->_Notify(
        StatData => $Stat,
        Section  => 'All'
    );

    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatistics/StatsViewParameterWidget',
        Data         => {

            #%Frontend,
            %{$Stat},
        },
    );
    return $Output;
}

sub _Notify {
    my ( $Self, %Param ) = @_;

    my $NotifyOutput = '';

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # check if need params are available
    for (qw(StatData Section)) {
        if ( !$Param{$_} ) {
            return $LayoutObject->ErrorScreen( Message => "_Notify: Need $_!" );
        }
    }

    # CompletenessCheck
    my @Notify = $Self->{StatsObject}->CompletenessCheck(
        StatData => $Param{StatData},
        Section  => $Param{Section},
    );
    for my $Ref (@Notify) {
        $NotifyOutput .= $LayoutObject->Notify( %{$Ref} );
    }
    return $NotifyOutput;
}

sub _StopWordsServerErrorsGet {
    my ( $Self, %Param ) = @_;

    # get needed objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    if ( !%Param ) {
        $LayoutObject->FatalError( Message => "Got no values to check." );
    }

    my %StopWordsServerErrors;
    if ( !$TicketObject->SearchStringStopWordsUsageWarningActive() ) {
        return %StopWordsServerErrors;
    }

    my %SearchStrings;

    FIELD:
    for my $Field ( sort keys %Param ) {
        next FIELD if !defined $Param{$Field};
        next FIELD if !length $Param{$Field};

        $SearchStrings{$Field} = $Param{$Field};
    }

    if (%SearchStrings) {

        my $StopWords = $TicketObject->SearchStringStopWordsFind(
            SearchStrings => \%SearchStrings
        );

        FIELD:
        for my $Field ( sort keys %{$StopWords} ) {
            next FIELD if !defined $StopWords->{$Field};
            next FIELD if ref $StopWords->{$Field} ne 'ARRAY';
            next FIELD if !@{ $StopWords->{$Field} };

            $StopWordsServerErrors{ $Field . 'Invalid' }        = 'ServerError';
            $StopWordsServerErrors{ $Field . 'InvalidTooltip' } = $LayoutObject->{LanguageObject}->Translate(
                'Please remove the following words because they cannot be used for the ticket restrictions:'
                )
                . ' '
                . join( ',', sort @{ $StopWords->{$Field} } );
        }
    }

    return %StopWordsServerErrors;
}

sub _StopWordFieldsGet {
    my ( $Self, %Param ) = @_;

    my %StopWordFields = (
        'From'    => 1,
        'To'      => 1,
        'Cc'      => 1,
        'Subject' => 1,
        'Body'    => 1,
    );

    return %StopWordFields;
}

1;
