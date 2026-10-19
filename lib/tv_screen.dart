import 'package:flutter/material.dart';
import 'core.dart';
import 'widgets.dart';

class TVDashboardView extends StatefulWidget {
  final bool isSideMenuOpen;
  final VoidCallback onOpenSideMenu;
  final VoidCallback onCloseSideMenu;
  final MainSection activeSection;
  final String sectionTitle;
  final String selectedCategory;
  final List<String> sectionCategories;
  final Map<String, int> categoryCounts;
  final List<StreamItem> displayedItems;
  final List<SeriesGroup> displayedSeries;
  final Map<String, VodProgressEntry> vodProgressMap;
  final Set<String> favoriteIds;
  final StreamItem? activeItem;
  final EpgProgramInfo? activeEpg;
  final Widget miniVideoWidget;
  final ValueChanged<MainSection> onSelectSection;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<StreamItem> onStartPreview;
  final ValueChanged<StreamItem> onOpenFullScreen;
  final ValueChanged<SeriesGroup> onSelectSeriesGroup;
  final ValueChanged<StreamItem> onToggleFavorite;
  final TextEditingController? searchController;
  final String searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onClearSearch;
  final VoidCallback? onRefreshPlaylist;
  final VoidCallback? onLogout;

  const TVDashboardView({
    super.key,
    required this.isSideMenuOpen,
    required this.onOpenSideMenu,
    required this.onCloseSideMenu,
    required this.activeSection,
    required this.sectionTitle,
    required this.selectedCategory,
    required this.sectionCategories,
    required this.categoryCounts,
    required this.displayedItems,
    required this.displayedSeries,
    required this.vodProgressMap,
    required this.favoriteIds,
    required this.activeItem,
    this.activeEpg,
    required this.miniVideoWidget,
    required this.onSelectSection,
    required this.onSelectCategory,
    required this.onStartPreview,
    required this.onOpenFullScreen,
    required this.onSelectSeriesGroup,
    required this.onToggleFavorite,
    this.searchController,
    this.searchQuery = '',
    this.onSearchChanged,
    this.onClearSearch,
    this.onRefreshPlaylist,
    this.onLogout,
  });

  @override
  State<TVDashboardView> createState() => _TVDashboardViewState();
}

class _TVDashboardViewState extends State<TVDashboardView> {
  final FocusNode _sideMenuFocus = FocusNode();
  StreamItem? _focusedVodItem;
  SeriesGroup? _focusedSeriesGroup;
  bool _adultUnlocked = false;

  final Color _bgColor = const Color(0xFF090B10);
  final Color _panelColor = const Color(0xFF111520);
  final Color _cardColor = const Color(0xFF161B2A);
  final Color _accentColor = const Color(0xFF00E5FF);
  final Color _secondaryAccent = const Color(0xFF7C4DFF);

  @override
  void dispose() {
    _sideMenuFocus.dispose();
    super.dispose();
  }

  void _focusSideMenuNow() {
    if (!widget.isSideMenuOpen) widget.onOpenSideMenu();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _sideMenuFocus.canRequestFocus) {
        _sideMenuFocus.requestFocus();
      }
    });
  }

  void _updateFocusedVod(StreamItem item) {
    if (_focusedVodItem?.id != item.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _focusedVodItem = item);
      });
    }
  }

  void _updateFocusedSeries(SeriesGroup series) {
    if (_focusedSeriesGroup?.id != series.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _focusedSeriesGroup = series);
      });
    }
  }

  bool _isCategoryAdult(String cat) {
    final lower = cat.toLowerCase();
    return lower.contains('adult') ||
        lower.contains('+18') ||
        lower.contains('18+') ||
        lower.contains('xxx') ||
        lower.contains('erot');
  }

  Future<void> _handleCategorySelect(String cat) async {
    if (_isCategoryAdult(cat) && !_adultUnlocked) {
      final unlocked = await showParentalPinPrompt(context, deviceMode: DeviceMode.tv);
      if (!unlocked || !mounted) return;
      setState(() => _adultUnlocked = true);
    }
    widget.onSelectCategory(cat);
  }

  // Pré-visualização só começa quando o usuário clica no canal (1º clique = Preview, 2º clique = Tela Cheia)
  Future<void> _handleChannelSelect(StreamItem item) async {
    if (item.isAdult && !_adultUnlocked) {
      final unlocked = await showParentalPinPrompt(context, deviceMode: DeviceMode.tv);
      if (!unlocked || !mounted) return;
      setState(() => _adultUnlocked = true);
    }

    if (widget.activeItem?.id == item.id) {
      widget.onOpenFullScreen(item);
    } else {
      widget.onStartPreview(item);
    }
  }

  Future<void> _handleVodSelect(StreamItem item) async {
    if (item.isAdult && !_adultUnlocked) {
      final unlocked = await showParentalPinPrompt(context, deviceMode: DeviceMode.tv);
      if (!unlocked || !mounted) return;
      setState(() => _adultUnlocked = true);
    }
    widget.onStartPreview(item);
  }

  Future<void> _handleFullScreen(StreamItem item) async {
    if (item.isAdult && !_adultUnlocked) {
      final unlocked = await showParentalPinPrompt(context, deviceMode: DeviceMode.tv);
      if (!unlocked || !mounted) return;
      setState(() => _adultUnlocked = true);
    }
    widget.onOpenFullScreen(item);
  }

  Future<void> _handleSeriesSelect(SeriesGroup series) async {
    if (series.isAdult && !_adultUnlocked) {
      final unlocked = await showParentalPinPrompt(context, deviceMode: DeviceMode.tv);
      if (!unlocked || !mounted) return;
      setState(() => _adultUnlocked = true);
    }
    widget.onSelectSeriesGroup(series);
  }

  void _openSearchKeyboard() {
    if (widget.searchController == null) return;
    showTVVirtualKeyboard(
      context,
      widget.searchController!,
      'Pesquisar em ${widget.sectionTitle}',
      onChanged: widget.onSearchChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLive = widget.activeSection == MainSection.live;

    return Scaffold(
      backgroundColor: _bgColor,
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: widget.isSideMenuOpen ? 230 : 60,
            decoration: BoxDecoration(
              color: _panelColor,
              border: Border(right: BorderSide(color: Colors.white.withOpacity(0.06))),
            ),
            child: widget.isSideMenuOpen ? _buildExpandedMenu() : _buildCollapsedRail(),
          ),
          Expanded(
            child: isLive ? _buildLiveTVLayout() : _buildImmersiveVodLayout(),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTVLayout() {
    return Row(
      children: [
        // COLUNA 1: CATEGORIAS
        Container(
          width: 235,
          color: _bgColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 12, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CATEGORIAS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withOpacity(0.55),
                        letterSpacing: 1.4,
                      ),
                    ),
                    if (widget.searchController != null)
                      TVIconButton(
                        icon: Icons.search_rounded,
                        color: _accentColor,
                        size: 18,
                        onPressed: _openSearchKeyboard,
                      ),
                  ],
                ),
              ),
              if (widget.searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: TVFocusableItem(
                    autoScroll: false,
                    onSelect: () => widget.onClearSearch?.call(),
                    builder: (c, f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: f ? Colors.white : Colors.redAccent),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Busca: "${widget.searchQuery}"',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.white),
                            ),
                          ),
                          const Icon(Icons.close, size: 14, color: Colors.redAccent),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  itemCount: widget.sectionCategories.length,
                  itemBuilder: (context, idx) {
                    final cat = widget.sectionCategories[idx];
                    final count = widget.categoryCounts[cat] ?? 0;
                    final isSel = cat == widget.selectedCategory;
                    final isAdultCat = _isCategoryAdult(cat);

                    return TVFocusableItem(
                      autofocus: !widget.isSideMenuOpen && isSel,
                      onMoveLeft: _focusSideMenuNow,
                      onSelect: () => _handleCategorySelect(cat),
                      builder: (c, f) => AnimatedContainer(
                        duration: const Duration(milliseconds: 130),
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: isSel
                              ? _accentColor.withOpacity(0.16)
                              : f
                                  ? Colors.white.withOpacity(0.07)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: f
                                ? _accentColor
                                : (isSel ? _accentColor.withOpacity(0.45) : Colors.transparent),
                            width: f ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            if (isAdultCat && !_adultUnlocked) ...[
                              const Icon(Icons.lock_outline_rounded, size: 14, color: Colors.redAccent),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                cat,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isSel ? _accentColor : Colors.white,
                                  fontWeight: isSel || f ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 11,
                                color: isSel ? _accentColor : Colors.white38,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // COLUNA 2: GRADE DE CANAIS (SÓ INICIA PRÉ-VISUALIZAÇÃO QUANDO CLICAR COM OK)
        Expanded(
          child: Container(
            color: _panelColor.withOpacity(0.45),
            child: widget.displayedItems.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum canal encontrado nesta categoria.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 285,
                      mainAxisExtent: 82,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: widget.displayedItems.length,
                    itemBuilder: (context, idx) {
                      final item = widget.displayedItems[idx];
                      final isPlaying = widget.activeItem?.id == item.id;
                      final isFav = widget.favoriteIds.contains(item.id);
                      final isLocked = item.isAdult && !_adultUnlocked;

                      return TVFocusableItem(
                        onSelect: () => _handleChannelSelect(item),
                        builder: (c, f) => AnimatedScale(
                          scale: f ? 1.04 : 1.0,
                          duration: const Duration(milliseconds: 120),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 130),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isPlaying ? _accentColor.withOpacity(0.15) : _cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: f
                                    ? _accentColor
                                    : isPlaying
                                        ? _secondaryAccent
                                        : Colors.white.withOpacity(0.06),
                                width: f ? 2.4 : 1.2,
                              ),
                              boxShadow: f
                                  ? [
                                      BoxShadow(
                                        color: _accentColor.withOpacity(0.24),
                                        blurRadius: 10,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                buildChannelLogo(item.logo, size: 46, isLocked: isLocked),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          if (isFav)
                                            const Icon(Icons.star_rounded, color: Colors.amber, size: 15),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          buildQualityBadge(item.qualityTag),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              isPlaying ? '▶ OK p/ Tela Cheia' : item.group,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: isPlaying ? _accentColor : Colors.white54,
                                                fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),

        // COLUNA 3: DOCK DE PRÉ-VISUALIZAÇÃO
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: _bgColor,
            border: Border(left: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PRÉ-VISUALIZAÇÃO',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.55),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.4,
                    ),
                  ),
                  if (widget.activeItem != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'AO VIVO',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: Colors.black,
                    child: widget.activeItem != null && widget.activeItem!.isAdult && !_adultUnlocked
                        ? const Center(
                            child: Icon(Icons.lock_rounded, color: Colors.redAccent, size: 42),
                          )
                        : widget.miniVideoWidget,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (widget.activeItem != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildChannelLogo(
                      widget.activeItem!.logo,
                      size: 42,
                      isLocked: widget.activeItem!.isAdult && !_adultUnlocked,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.activeItem!.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.activeItem!.group,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: _accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (widget.activeEpg != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _panelColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.activeEpg!.nowTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: widget.activeEpg!.progress,
                          minHeight: 3,
                          backgroundColor: Colors.white12,
                          color: _accentColor,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.activeEpg!.nextTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: TVFocusableItem(
                    autoScroll: false,
                    onSelect: () => _handleFullScreen(widget.activeItem!),
                    builder: (c, f) => AnimatedScale(
                      scale: f ? 1.04 : 1.0,
                      duration: const Duration(milliseconds: 120),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: f ? Colors.white : _accentColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            'TELA CHEIA',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TVFocusableItem(
                    autoScroll: false,
                    onSelect: () => SharedStreamEngine.instance.openStream(
                      widget.activeItem!,
                      forceReload: true,
                      tryHlsFallback: true,
                    ),
                    builder: (c, f) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: f ? Colors.white.withOpacity(0.12) : _panelColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: f ? _accentColor : Colors.white12),
                      ),
                      child: const Center(
                        child: Text(
                          'Alternar Formato (TS / HLS)',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TVFocusableItem(
                    autoScroll: false,
                    onSelect: () => widget.onToggleFavorite(widget.activeItem!),
                    builder: (c, f) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: f ? Colors.white.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: f ? Colors.white : Colors.white24),
                      ),
                      child: Center(
                        child: Text(
                          widget.favoriteIds.contains(widget.activeItem!.id)
                              ? '★ Remover Favorito'
                              : '☆ Adicionar Favorito',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: f ? Colors.white : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImmersiveVodLayout() {
    final isSeries = widget.activeSection == MainSection.series;
    final bgUrl = isSeries ? _focusedSeriesGroup?.logo : _focusedVodItem?.logo;
    final isFocusedAdultLocked = isSeries
        ? ((_focusedSeriesGroup?.isAdult ?? false) && !_adultUnlocked)
        : ((_focusedVodItem?.isAdult ?? false) && !_adultUnlocked);

    final title = isSeries
        ? (_focusedSeriesGroup?.title ?? widget.sectionTitle)
        : (_focusedVodItem?.name ?? widget.sectionTitle);
    final synopsis = isSeries
        ? (_focusedSeriesGroup?.synopsis ??
            'Selecione uma série abaixo para ver todas as temporadas e episódios.')
        : (_focusedVodItem?.synopsis != 'Nenhuma sinopse disponível.' &&
                _focusedVodItem?.synopsis != null
            ? _focusedVodItem!.synopsis
            : 'Pressione OK no pôster para abrir a ficha técnica, sinopse completa ou iniciar a reprodução.');
    final badge = isSeries ? _focusedSeriesGroup?.qualityTag : _focusedVodItem?.qualityTag;
    final rating = isSeries ? _focusedSeriesGroup?.rating : _focusedVodItem?.rating;
    final groupName = isSeries ? _focusedSeriesGroup?.group : _focusedVodItem?.group;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (bgUrl != null && bgUrl.isNotEmpty && !isFocusedAdultLocked)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.72,
            child: Image.network(
              bgUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              cacheWidth: 640,
              errorBuilder: (_, __, ___) => Container(color: _bgColor),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _bgColor.withOpacity(0.35),
                _bgColor.withOpacity(0.86),
                _bgColor,
              ],
              stops: const [0.0, 0.45, 0.80],
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
              child: SizedBox(
                height: 38,
                child: Row(
                  children: [
                    if (widget.searchController != null) ...[
                      TVFocusableItem(
                        autoScroll: false,
                        onMoveLeft: _focusSideMenuNow,
                        onSelect: _openSearchKeyboard,
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: f ? _accentColor : _panelColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: f ? Colors.white : Colors.white24),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search, size: 16, color: f ? Colors.black : _accentColor),
                              const SizedBox(width: 6),
                              Text(
                                widget.searchQuery.isEmpty ? 'Pesquisar' : '"${widget.searchQuery}"',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: f ? Colors.black : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.searchQuery.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        TVIconButton(
                          icon: Icons.close_rounded,
                          size: 16,
                          color: Colors.redAccent,
                          onPressed: () => widget.onClearSearch?.call(),
                        ),
                      ],
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.sectionCategories.length,
                        itemBuilder: (context, idx) {
                          final cat = widget.sectionCategories[idx];
                          final isSel = cat == widget.selectedCategory;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: TVFocusableItem(
                              autoScroll: false,
                              onSelect: () => _handleCategorySelect(cat),
                              builder: (c, f) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? _accentColor
                                      : f
                                          ? Colors.white24
                                          : _panelColor.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: f ? Colors.white : Colors.white12),
                                ),
                                child: Text(
                                  cat,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSel ? Colors.black : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 16, 36, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        if (badge != null) buildQualityBadge(badge),
                        if (rating != null && rating != 'N/A' && rating.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(
                            '★ $rating',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                        if (groupName != null && groupName.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(
                            '• $groupName',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _accentColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 680,
                      child: Text(
                        synopsis,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.white.withOpacity(0.78),
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 265,
              child: isSeries
                  ? widget.displayedSeries.isEmpty
                      ? const Center(
                          child: Text('Nenhuma série encontrada.', style: TextStyle(color: Colors.white54)),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 10),
                          itemCount: widget.displayedSeries.length,
                          itemBuilder: (context, idx) {
                            final s = widget.displayedSeries[idx];
                            final locked = s.isAdult && !_adultUnlocked;
                            return TVFocusableItem(
                              autofocus: idx == 0 && !widget.isSideMenuOpen,
                              onMoveLeft: idx == 0 ? _focusSideMenuNow : null,
                              onSelect: () => _handleSeriesSelect(s),
                              builder: (c, f) {
                                if (f) _updateFocusedSeries(s);
                                return Padding(
                                  padding: const EdgeInsets.only(right: 18),
                                  child: AspectRatio(
                                    aspectRatio: 0.68,
                                    child: buildStreamingPosterCard(
                                      title: s.title,
                                      subtitle: s.group,
                                      logoUrl: s.logo,
                                      badgeText: s.qualityTag,
                                      isFocused: f,
                                      isAdultLocked: locked,
                                      onTap: () => _handleSeriesSelect(s),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        )
                  : widget.displayedItems.isEmpty
                      ? const Center(
                          child: Text('Nenhum conteúdo encontrado.', style: TextStyle(color: Colors.white54)),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 10),
                          itemCount: widget.displayedItems.length,
                          itemBuilder: (context, idx) {
                            final item = widget.displayedItems[idx];
                            final isFav = widget.favoriteIds.contains(item.id);
                            final prog = widget.vodProgressMap[item.id];
                            final locked = item.isAdult && !_adultUnlocked;
                            return TVFocusableItem(
                              autofocus: idx == 0 && !widget.isSideMenuOpen,
                              onMoveLeft: idx == 0 ? _focusSideMenuNow : null,
                              onSelect: () => _handleVodSelect(item),
                              builder: (c, f) {
                                if (f) _updateFocusedVod(item);
                                return Padding(
                                  padding: const EdgeInsets.only(right: 18),
                                  child: AspectRatio(
                                    aspectRatio: 0.68,
                                    child: buildStreamingPosterCard(
                                      title: item.name,
                                      subtitle: item.group,
                                      logoUrl: item.logo,
                                      badgeText: item.qualityTag,
                                      isFocused: f,
                                      isFavorite: isFav,
                                      isAdultLocked: locked,
                                      progress: prog?.progress,
                                      onTap: () => _handleVodSelect(item),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ],
    );
  }

  Widget _buildCollapsedRail() {
    return Column(
      children: [
        const SizedBox(height: 22),
        Icon(Icons.play_circle_fill_rounded, color: _accentColor, size: 28),
        const SizedBox(height: 20),
        _buildRailIcon(Icons.live_tv_rounded, MainSection.live),
        _buildRailIcon(Icons.movie_creation_rounded, MainSection.movie),
        _buildRailIcon(Icons.video_library_rounded, MainSection.series),
        _buildRailIcon(Icons.play_circle_outline_rounded, MainSection.continueWatching),
        _buildRailIcon(Icons.star_rounded, MainSection.favorites),
        _buildRailIcon(Icons.history_rounded, MainSection.recents),
      ],
    );
  }

  Widget _buildRailIcon(IconData icon, MainSection sec) {
    final sel = widget.activeSection == sec;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TVFocusableItem(
        autoScroll: false,
        onSelect: _focusSideMenuNow,
        builder: (c, f) {
          if (f) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _focusSideMenuNow());
          }
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: sel ? _accentColor.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: sel ? _accentColor : Colors.white54),
          );
        },
      ),
    );
  }

  Widget _buildExpandedMenu() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 18),
          child: Text(
            'UNEX VISION',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: _accentColor,
              fontSize: 16,
              letterSpacing: 1.5,
            ),
          ),
        ),
        _buildNav('TV ao Vivo', MainSection.live, Icons.live_tv_rounded),
        _buildNav('Filmes', MainSection.movie, Icons.movie_creation_rounded),
        _buildNav('Séries', MainSection.series, Icons.video_library_rounded),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(color: Colors.white10),
        ),
        _buildNav('Continuar Assistindo', MainSection.continueWatching, Icons.play_circle_filled_rounded),
        _buildNav('Meus Favoritos', MainSection.favorites, Icons.star_rounded),
        _buildNav('Recentes', MainSection.recents, Icons.history_rounded),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(color: Colors.white10),
        ),
        TVFocusableItem(
          onMoveRight: widget.onCloseSideMenu,
          onSelect: () {
            widget.onCloseSideMenu();
            showChangeParentalPinDialog(context, deviceMode: DeviceMode.tv);
          },
          builder: (c, f) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: f ? Colors.white.withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_person_rounded, size: 20, color: Colors.white70),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Senha Parental', style: TextStyle(fontSize: 12.5, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
        if (widget.onRefreshPlaylist != null)
          TVFocusableItem(
            onMoveRight: widget.onCloseSideMenu,
            onSelect: () {
              widget.onCloseSideMenu();
              widget.onRefreshPlaylist!();
            },
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: f ? Colors.white.withOpacity(0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.refresh_rounded, size: 20, color: Colors.white70),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Atualizar Lista', style: TextStyle(fontSize: 12.5, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        if (widget.onLogout != null)
          TVFocusableItem(
            onMoveRight: widget.onCloseSideMenu,
            onSelect: widget.onLogout!,
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: f ? Colors.redAccent.withOpacity(0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.logout_rounded, size: 20, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Trocar Conta',
                      style: TextStyle(fontSize: 12.5, color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNav(String label, MainSection section, IconData icon) {
    final sel = widget.activeSection == section;
    return TVFocusableItem(
      focusNode: sel ? _sideMenuFocus : null,
      autofocus: sel,
      onMoveRight: widget.onCloseSideMenu,
      onSelect: () => widget.onSelectSection(section),
      builder: (c, f) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: sel ? _accentColor : (f ? Colors.white.withOpacity(0.08) : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: sel ? Colors.black : Colors.white70),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: sel ? Colors.black : Colors.white,
                  fontWeight: sel ? FontWeight.w900 : FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
