function mk
    if test (count $argv) -eq 0
        echo "Usage: mk <directory_name>"
        return 1
    end
    mkdir -p $argv[1] && cd $argv[1]
end
