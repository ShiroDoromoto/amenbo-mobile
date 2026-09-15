# ルートの Makefile は束ねるだけ。
#
# ビルドの実体は `app/Makefile` が持ち、ここはそこへ渡す。**渡す先が1つになっても、ここは残す**
# ——リポジトリ直下は Flutter に渡さないと決めてあり（→ README.md「構成」）、`guards/` のように
# アプリの外にある検査も束ねる相手だからである。
#
#   make app                     アプリだけをビルドする
#   make build / test / clean    束ねる側から。`test` はガードを先に回す
#
# Makefile を持たない部品は飛ばす。

PARTS := app

.DEFAULT_GOAL := help

# $(1) 部品名 / $(2) その部品の Makefile に渡すターゲット
define delegate
	@if [ -f $(1)/Makefile ]; then \
		echo "==> $(1): $(2)"; \
		$(MAKE) -C $(1) $(2); \
	else \
		echo "==> $(1): Makefile がまだ無いので飛ばす"; \
	fi
endef

help:
	@echo 'make app      アプリ（Flutter）をビルドする'
	@echo 'make build    すべてビルドする'
	@echo 'make test     ガード ＋ すべてのテストを走らせる'
	@echo 'make guards   ツリーの形を見るガードだけを走らせる'
	@echo 'make clean    生成物を消す'

build: $(addprefix build-,$(PARTS))
test: guards $(addprefix test-,$(PARTS))
clean: $(addprefix clean-,$(PARTS))

# 部品に属さない検査。見ているのはツリーの形——`app/Makefile` には置けないので、束ねる側が持つ。
# CI の guards ジョブもこれを回す。数秒で終わるので、部品ごとの反復とは別に締めで通ればよい。
guards:
	@set -e; for g in guards/*.sh; do "$$g"; done

$(addprefix build-,$(PARTS)): build-%:
	$(call delegate,$*,build)

$(addprefix test-,$(PARTS)): test-%:
	$(call delegate,$*,test)

$(addprefix clean-,$(PARTS)): clean-%:
	$(call delegate,$*,clean)

# `make app` のように部品名だけで呼べる短縮。部品名はディレクトリ名でもあるので、
# .PHONY に入れておかないと「もう在る」と見なされて何も走らない。
$(PARTS): %: build-%

.PHONY: help build test clean guards $(PARTS) \
	$(addprefix build-,$(PARTS)) \
	$(addprefix test-,$(PARTS)) \
	$(addprefix clean-,$(PARTS))
