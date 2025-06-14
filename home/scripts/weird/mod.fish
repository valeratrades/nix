set current_dir_weird (dirname (status --current-filename))
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
    cat $current_dir_weird/sbf_tweet.txt | python3 $current_dir_weird/what.py | figlet
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
    fontsize 22
    printf 'Will be\nright back' | figlet | $PAGER
    fontsize "$current_fontsize"
end
