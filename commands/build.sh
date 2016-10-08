#!/bin/bash

dir="$(pwd)"
cd $(cd "$(dirname "$0")"; pwd)/..

watch=''
test=''
simpletest=''

if [ "${1}" == '--watch' ] ; then
	watch=true
elif [ "${1}" == '--test' ] ; then
	test=true
elif [ "${1}" == '--simpletest' ] ; then
	simpletest=true
fi

tsargs="$(node -e '
	const compilerOptions	= JSON.parse(
		'"'$(cat shared/js/tsconfig.json | tr '\n' ' ')'"'
	).compilerOptions;

	console.log(Object.keys(compilerOptions).map(k => {
		const v			= compilerOptions[k];
		let argValue	= "";

		if (v === false) {
			return;
		}
		else if (v !== true) {
			argValue	= " " + v.toString();
		}

		return `--${k}${argValue}`;
	}).join(" "));
')"

tsfiles="$( \
	{ \
		find . -name '*.html' -not \( -path './websign/*' -or -path '*/lib/*' \) -exec cat {} \; | \
		grep -oP "src=(['\"])/js/.*?\1" & \
		grep -roP "importScripts\((['\"])/js/.*\1\)" shared/js; \
	} | \
		perl -pe "s/.*?['\"]\/js\/(.*)\.js.*/\1/g" | \
		sort | \
		uniq | \
		grep -v 'Binary file' | \
		tr '\n' ' ' \
)"

cd $dir
if [ -f build.sh ] ; then
	cd ..
fi
if [ -d shared ] ; then
	cd shared
fi

scssfiles="$(find css -name '*.scss' | grep -v bourbon/ | perl -pe 's/(.*)\.scss/\1/g' | tr '\n' ' ')"


rm lib/js/node_modules js/node_modules 2> /dev/null
cd lib/js
ln -s . node_modules
cd ../../js
ln -s ../lib/js node_modules
cd ..


output=''

compile () {
	for file in $scssfiles ; do
		command="scss -Icss $file.scss $file.css"
		if [ "${watch}" ] ; then
			$command &
		else
			output="${output}$($command)"
		fi
	done

	cd js

	output="${output}$(tsc $tsargs $(for f in $tsfiles ; do echo $f.ts ; done))"

	if [ ! "${simpletest}" ] ; then
		find . -name '*.js' -not -path './node_modules/*' -exec node -e '
			const watch	= "'"${watch}"'";

			const build	= f => {
				const path		= fs.realpathSync(f);
				const parent	= path.split("/").slice(0, -1).join("/");

				const input		= fs.readFileSync(path).toString();
				const content	= (
					watch ?
						input :
						child_process.spawnSync("babel", [
							"--presets",
							"es2015",
							"--compact",
							"false"
						], {input}).stdout.toString()
				).trim().replace(
					/\/\/\/ <reference path="(.*)".*/g,
					(_, sub) => sub.match(/\.d\.ts$/) ?
						"" :
						build(parent + "/" + sub.replace(/\.ts$/, ".js"))
				);

				fs.writeFileSync(path, content);

				return content;
			};

			build("{}");
		' \;

		for file in $tsfiles ; do
			webpack \
				--optimize-dedupe \
				--output-library-target var \
				--output-library "$(echo $file | perl -pe 's/.*\/([^\/]+)$/\u$1/')" \
				$file.js \
				$file.js.tmp

			cat $file.js.tmp | sed 's|use strict||g' > $file.js
			rm $file.js.tmp
		done
	fi

	cd ..
}

if [ "${watch}" ] ; then
	while true ; do
		start="$(date +%s)"
		echo -e '\n\n\nBuilding JS/CSS\n\n'
		compile
		echo -e "\n\n\nFinished building JS/CSS ($(expr $(date +%s) - $start)s)\n\n"
		inotifywait -r --exclude '(node_modules|sed.*|.*\.(html|css|js|map|tmp))$' css js
	done
else
	compile
fi

echo -e "${output}"

rm lib/js/node_modules js/node_modules

if [ "${test}" -o "${simpletest}" ] ; then
	{ \
		find css -name '*.css' & \
		find css -name '*.map' & \
		find js -name '*.js' & \
		find js -name '*.map'; \
	} | xargs -I% rm %
fi

exit ${#output}
