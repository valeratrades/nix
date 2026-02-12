set __fish_scripts_weird_dir (dirname (status --current-filename))
alias emacs="printf \"\033[31mno\033[0m\n\""
alias nano="printf \"\033[31mno\033[0m\n\""

function print_sturdy
    echo "+---+---+---+---+---++---+---+---+---+---+"
    echo "┊ V ┊ M ┊ L ┊ C ┊ P    X ┊ F ┊ O ┊ U ┊ J ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ S ┊ T ┊ R ┊ D ┊ Y    . ┊ N ┊ A ┊ E ┊ I ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ Z ┊ K ┊ Q ┊ G ┊ W    B ┊ H ┊ ' ┊ ; ┊ , ┊"
    echo "+---+---+---+---+---++---+---+---+---+---+"
end

function print_dvorak
    echo "+---+---+---+---+---++---+---+---+---+---+"
    echo "┊ ' ┊ , ┊ . ┊ P ┊ Y    F ┊ G ┊ C ┊ R ┊ L ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ A ┊ O ┊ E ┊ U ┊ I    D ┊ H ┊ T ┊ N ┊ S ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ ; ┊ Q ┊ J ┊ K ┊ X    B ┊ M ┊ W ┊ V ┊ Z ┊"
    echo "+---+---+---+---+---++---+---+---+---+---+"
end

function print_semimak_original
    echo "+---+---+---+---+---++---+---+---+---+---+"
    echo "┊ F ┊ L ┊ H ┊ V ┊ Z    Q ┊ W ┊ U ┊ O ┊ Y ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ S ┊ R ┊ N ┊ T ┊ K    C ┊ D ┊ E ┊ A ┊ I ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ X ┊ ' ┊ B ┊ M ┊ J    P ┊ G ┊ , ┊ . ┊ / ┊"
    echo "+---+---+---+---+---++---+---+---+---+---+"
end

function print_semimak
    echo "+---+---+---+---+---++---+---+---+---+---+"
    echo "┊ F ┊ L ┊ H ┊ V ┊ Z    Q ┊ W ┊ U ┊ O ┊ Y ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ S ┊ R ┊ N ┊ T ┊ K    C ┊ D ┊ E ┊ A ┊ I ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ X ┊ ' ┊ B ┊ M ┊ J    P ┊ G ┊ , ┊ . ┊ ; ┊"
    echo "+---+---+---+---+---++---+---+---+---+---+"
end
function print_semimak_alt
    echo "+---+---+---+---+---++---+---+---+---+---+"
    echo "┊ F ┊ L ┊ H ┊ V ┊ Z    Qü┊ Wù┊ Uû┊ Oô┊ Yï┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ Sß┊ R ┊ N ┊ T ┊ K    Cç┊ Dê┊ Eé┊ Aà┊ Iî┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ X ┊ ' ┊ B ┊ M ┊ J    P ┊ Gö┊ ,è┊ .â┊ ;ä┊"
    echo "+---+---+---+---+---++---+---+---+---+---+"
end

function print_qwerty
    echo "+---+---+---+---+---++---+---+---+---+---+"
    echo "┊ Q ┊ W ┊ E ┊ R ┊ T    Y ┊ U ┊ I ┊ O ┊ P ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ A ┊ S ┊ D ┊ F ┊ G    H ┊ J ┊ K ┊ L ┊ ; ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊"
    echo "┊ Z ┊ X ┊ C ┊ V ┊ B    N ┊ M ┊ , ┊ . ┊ / ┊"
    echo "+---+---+---+---+---++---+---+---+---+---+"
end

function print_ru
    echo "+---+---+---+---+---++---+---+---+---+---+---+---+"
    echo "┊ Й ┊ Ц ┊ У ┊ К ┊ Е    Н ┊ Г ┊ Ш ┊ Щ ┊ З ┊ Х | Ъ ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊---┊---+"
    echo "┊ Ф ┊ Ы ┊ В ┊ А ┊ П    Р ┊ О ┊ Л ┊ Д ┊ Ж ┊ Э ┊"
    echo "┊---┊---┊---┊---┊---  ---┊---┊---┊---┊---┊---+"
    echo "┊ Я ┊ Ч ┊ С ┊ М ┊ И    Т ┊ Ь ┊ Б ┊ Ю ┊ . ┊"
    echo "+---+---+---+---+---++---+---+---+---+---+"
end

function print_alphabet
    echo "a b c d e f g h i j"
    echo "k l m n o p q r s t"
    echo "u v w x y z"
end

function typing_guide
    google-chrome-stable "https://docs.google.com/document/d/1L-P68VDSGlpLM5A9tfRvWFohaR2NzPbkUT0ok34rsFU/edit"
end

function what
    cat $__fish_scripts_weird_dir/sbf_tweet.txt | python3 $__fish_scripts_weird_dir/what.py | figlet
end

alias bad_apple="bad-apple-rs"

function russian_roulette
    set r (math (random) % 6)
    if test $r -eq 0
        /usr/bin/emacs $argv[1]; or /usr/bin/emacs
    else
        $EDITOR $argv
    end
end

function brb
    set current_fontsize (fontsize)

    # mute mic
    wpctl set-mute @DEFAULT_SOURCE@ 1

    # halt time tracker, remember if we should resume
    set should_resume false
    set halt_output (tedi blocker halt 2>&1)
    if test $status -eq 0; and not string match -q '*already stopped*' "$halt_output"
        set should_resume true
    end

    # switch OBS to stream-only scene if running
    set obs_running false
    if swaymsg -t get_tree | jq -e '.. | select(.app_id? == "com.obsproject.Studio")' >/dev/null 2>&1
        set obs_running true
        ~/.config/sway/send_keypress_to_window.rs com.obsproject.Studio s
    end

    fontsize 22
    printf 'Will be\nright back' | figlet | $PAGER
    fontsize "$current_fontsize"

    # unmute mic
    wpctl set-mute @DEFAULT_SOURCE@ 0

    # switch OBS back to both scene
    if test "$obs_running" = true
        ~/.config/sway/send_keypress_to_window.rs com.obsproject.Studio b
    end

    # resume time tracker if we halted it
    if test "$should_resume" = true
        tedi blocker resume
    end
end

function print_phonetic
    echo "+---+-----------++---+-----------+"
    echo "┊ A ┊ Alfa      ┊┊ N ┊ November  ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ B ┊ Bravo     ┊┊ O ┊ Oscar     ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ C ┊ Charlie   ┊┊ P ┊ Papa      ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ D ┊ Delta     ┊┊ Q ┊ Quebec    ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ E ┊ Echo      ┊┊ R ┊ Romeo     ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ F ┊ Foxtrot   ┊┊ S ┊ Sierra    ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ G ┊ Golf      ┊┊ T ┊ Tango     ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ H ┊ Hotel     ┊┊ U ┊ Uniform   ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ I ┊ India     ┊┊ V ┊ Victor    ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ J ┊ Juliett   ┊┊ W ┊ Whiskey   ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ K ┊ Kilo      ┊┊ X ┊ Xray      ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ L ┊ Lima      ┊┊ Y ┊ Yankee    ┊"
    echo "┊---┊-----------┊┊---┊-----------┊"
    echo "┊ M ┊ Mike      ┊┊ Z ┊ Zulu      ┊"
    echo "+---+-----------++---+-----------+"
end
