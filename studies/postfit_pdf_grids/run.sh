
#!/usr/bin/env bash
# Make the PDF grids and plot results

usage() {
    echo "Usage: run.sh <infile> -o <output_dir>" 
    echo "-f <short name of fitted PDF>"
    echo "-p <short name of pd PDF>"
    echo "-h, --help <show this help message>"
    exit 1
}

infile="/scratch/calexe/PostfitPdfStudies/w_z_gen_dists_maxFiles_m1_nnpdf40_pdMSHT20_masswindow.hdf5"
output_dir="/scratch/calexe/PostfitPdfStudies/GenFits/"
fittedPDF="nnpdf40"
pdPDF="msht20"

if [ -z "$1" ]; then
    usage
fi

input_file=$1
shift

PARSED=$(getopt -o o:f:p:h --long output:,fittedPDF:,pdPDF:,help -- "$@")
if [[ $? -ne 0 ]]; then
    echo "Failed to parse arguments." >&2
    exit 1
fi
eval set -- "$PARSED"

while true; do
    case "$1" in
        -o|--output)
            output_dir="$2"
            shift 2
            ;;
        -f|--fittedPDF)
            fittedPDF="$2"
            shift 2
            ;;
        -p|--pdPDF)
            pdPDF="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unexpected option: $1" >&2
            exit 1
            ;;
    esac
done

echo
echo "1) setupRabbit"

asterix_args=(
    --excludeNuisances '.*'
    --keepNuisances 'pdf.*'
)    

postfix_arg="${fittedPDF,,}_pd${pdPDF^^}"

setupRabbit_command="python3 ${WREM_BASE}/scripts/rabbit/setupRabbit.py -i $input_file --fitvar ptVgen-absYVgen -o $output_dir --filter Zmumu ${asterix_args[@]} --pseudoData nominal_gen_pdf${pdPDF^^} --postfix $postfix_arg -n nominal_gen --resumUnc none --npUnc none --asUncFromUncorr --noTheoryCorrsViaHel --scalePdf 1. --pseudoDataIdx 0 --pseudoDataAxes pdfVar"
echo
echo "$setupRabbit_command"
echo
setupRabbit_output=$($setupRabbit_command 2>&1 | tee /dev/tty)

echo
echo "2) rabbit_fit"

carrot=$(echo "$setupRabbit_output" | grep -oP '(?<=Write output file ).*')
carrot=$(echo "$carrot" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g') # sanitize the output
echo
echo "Rabbit file: $carrot"
output=$(dirname "$carrot")
echo "Output: $output"

rabbit_fit_command="rabbit_fit.py $carrot -t 0 --doImpacts --unblind --saveHists --saveHistsPerProcess --computeHistErrors -m BaseMapping -m Project ch0 absYVgen -m Project ch0 ptVgen --pseudoData nominal_gen_pdf${pdPDF^^}_pdfVar -o $output"
echo
echo "$rabbit_fit_command"
echo  
rabbit_fit_output=$($rabbit_fit_command 2>&1 | tee /dev/tty)


fit_result=$(echo "$rabbit_fit_output" | grep -oP '(?<=Results written in file ).*')

echo
echo "3) make_postfit_pdf_grids"

make_grids_cmd=(
    python3 "${WREM_BASE}/scripts/utilities/make_postfit_pdf_grids.py"
    --fitresult "$fit_result"
    -o "$output_dir"
    --pseudoData "nominal_gen_pdf${pdPDF^^}_pdfVar"
    -l "$postfix_arg"
)

echo
echo "${make_grids_cmd[@]}"
echo
make_grids_output=$("${make_grids_cmd[@]}" 2>&1 | tee /dev/tty)

fitted_pdf_long_name=$(echo "$make_grids_output" | grep -oP '(?<=PDFs in set )\w+')
pd_pdf_long_name=$(echo "$make_grids_output" | grep -oP 'pseudodata: "PDFSet<\K[^,]+')

echo
echo "4) plot pdfs"

# if the output plots dir doesn't exist, create it
output_plot_dir="${output_dir}/GenFit${fittedPDF^^}pd${pdPDF^^}/"
if [ ! -d "$output_plot_dir" ]; then
    mkdir -p "$output_plot_dir"
fi
echo
echo "Output plots directory: $output_plot_dir" 

plot_cmd=(
    python3 "${WREM_BASE}/scripts/plotting/plot_pdfs.py"
    --lhapdf-path "$output_dir"
    -s "$fitted_pdf_long_name" "$pd_pdf_long_name" "${fitted_pdf_long_name}_${postfix_arg}_unscaled"
    -o "$output_plot_dir"
    -l "${fittedPDF^^}" "${pdPDF^^}" "${fittedPDF^^} (gen fit ${pdPDF^^})"
    -f dv uv 1 2 3
    --colors r g b
)

echo
echo "${plot_cmd[@]}"
echo
plot_output=$("${plot_cmd[@]}" 2>&1 | tee /dev/tty)


