import 'package:flutter/material.dart';
import 'core.dart';
import 'widgets.dart';

class MobileDashboardView extends StatefulWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final MainSection activeSection;
  final String sectionTitle;
  final String selectedCategory;
  final List<String> sectionCategories;
  final Map<String, int> categoryCounts;
  final List<StreamItem> displayedItems;
  final List<SeriesGroup> displayedSeries;
  final List<VodProgressEntry> continueWatchingEntries;
  final Map<String, VodProgressEntry> vodProgressMap;
  final Set<String> favoriteIds;
  final StreamItem? activeItem;
  final EpgProgramInfo? activeEpg;
  final Widget miniVideoWidget;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<MainSection> onSelectSection;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<StreamItem> onStartPreview;
  final ValueChanged<StreamItem> onOpenFullScreen;
  final ValueChanged<SeriesGroup> onSelectSeriesGroup;
  final ValueChanged<StreamItem> onToggleFavorite;
  final VoidCallback? onRefreshPlaylist;
  final VoidCallback? onLogout;
  final VoidCallback? onSwitchToTVMode;

  const MobileDashboardView({
    super.key,
    required this.scaffoldKey,
    required this.activeSection,
    required this.sectionTitle,
    required this.selectedCategory,
    required this.sectionCategories,
    required this.categoryCounts,
    required this.displayedItems,
    required this.displayedSeries,
    required this.continueWatchingEntries,
    required this.vodProgressMap,
    required this.favoriteIds,
    required this.activeItem,
    required this.activeEpg,
    required this.miniVideoWidget,
    required this.searchController,
    required this.searchQuery,
    required this.onSelectSection,
    required this.onSelectCategory,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onStartPreview,
    required this.onOpenFullScreen,
    required this.onSelectSeriesGroup,
    required this.onToggleFavorite,
    this.onRefreshPlaylist,
    this.onLogout,
    this.onSwitchToTVMode,
  });

  @override
  State<MobileDashboardView> createState() => _MobileDashboardViewState();
}

class _MobileDashboardViewState extends State<MobileDashboardView> {
  bool _adultUnlocked = false;

  bool _isCategoryAdult(String cat) {
    final lower = cat.toLowerCase();
    return lower.contains('adult') ||
        lower.contains('+18') ||
        lower.contains('18+') ||
        lower.contains('xxx') ||
        lower.contains('erot');
  }

  Future<void> _handleCategoryTap(String cat) async {
    if (_isCategoryAdult(cat) && !_adultUnlocked) {
      final unlocked = await showParentalPinPrompt(context, deviceMode: DeviceMode.mobile);
      if (!unlocked || !mounted) return;
      setState(() => _adultUnlocked = true);
    }
    widget.onSelectCategory(cat);
  }

  Future<void> _handleItemTap(StreamItem item, {bool openFull = false}) async {
    if (item.isAdult && !_adultUnlocked) {
      final unlocked = await showParentalPinPrompt(context, deviceMode: DeviceMode.mobile);
      if (!unlocked || !mounted) return;
      setState(() => _adultUnlocked = true);
    }
    if (openFull) {
      widget.onOpenFullScreen(item);
    } else {
      widget.onStartPreview(item);
    }
  }

  Future<void> _handleSeriesTap(SeriesGroup series) async {
    if (series.isAdult && !_adultUnlocked) {
      final unlocked = await showParentalPinPrompt(context, deviceMode: DeviceMode.mobile);
      if (!unlocked || !mounted) return;
      setState(() => _adultUnlocked = true);
    }
    widget.onSelectSeriesGroup(series);
  }

  Widget buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF090B10),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF00E5FF), size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UNEX VISION',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF00E5FF),
                          letterSpacing: 1.4,
                        ),
                      ),
                      Text(
                        'Modo Celular • v2.0',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                children: [
                  _buildDrawerItem(context, 'TV ao Vivo', MainSection.live, Icons.live_tv_rounded),
                  _buildDrawerItem(context, 'Filmes', MainSection.movie, Icons.movie_creation_rounded),
                  _buildDrawerItem(context, 'Séries', MainSection.series, Icons.video_library_rounded),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: Colors.white10),
                  ),
                  _buildDrawerItem(
                    context,
                    'Continuar Assistindo',
                    MainSection.continueWatching,
                    Icons.play_circle_filled_rounded,
                  ),
                  _buildDrawerItem(context, 'Meus Favoritos', MainSection.favorites, Icons.star_rounded),
                  _buildDrawerItem(context, 'Recentes', MainSection.recents, Icons.history_rounded),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: Colors.white10),
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_person_rounded, color: Colors.white70),
                    title: const Text(
                      'Senha Parental (+18)',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      showChangeParentalPinDialog(context, deviceMode: DeviceMode.mobile);
                    },
                  ),
                  if (widget.onSwitchToTVMode != null)
                    ListTile(
                      leading: const Icon(Icons.tv_rounded, color: Color(0xFF00E5FF)),
                      title: const Text(
                        'Alternar para Modo TV',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onSwitchToTVMode!();
                      },
                    ),
                  if (widget.onRefreshPlaylist != null)
                    ListTile(
                      leading: const Icon(Icons.refresh_rounded, color: Colors.white70),
                      title: const Text(
                        'Atualizar Lista',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onRefreshPlaylist!();
                      },
                    ),
                  if (widget.onLogout != null)
                    ListTile(
                      leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                      title: const Text(
                        'Trocar Conta / Sair',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onLogout!();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, String title, MainSection section, IconData icon) {
    final sel = widget.activeSection == section;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: sel ? const Color(0xFF00E5FF).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: sel ? const Color(0xFF00E5FF).withOpacity(0.5) : Colors.transparent,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: sel ? const Color(0xFF00E5FF) : Colors.white70),
        title: Text(
          title,
          style: TextStyle(
            color: sel ? Colors.white : Colors.white70,
            fontWeight: sel ? FontWeight.w900 : FontWeight.bold,
            fontSize: 14,
          ),
        ),
        onTap: () {
          Navigator.pop(context);
          widget.onSelectSection(section);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSeries = widget.activeSection == MainSection.series;
    final isMovie = widget.activeSection == MainSection.movie ||
        widget.activeSection == MainSection.continueWatching;

    return Column(
      children: [
        // 1. BARRA SUPERIOR COMPACTA
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: const Color(0xFF0D1018),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu_rounded, color: Color(0xFF00E5FF)),
                onPressed: () => widget.scaffoldKey.currentState?.openDrawer(),
              ),
              Expanded(
                child: Text(
                  widget.sectionTitle,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
              if (widget.onRefreshPlaylist != null)
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                  tooltip: 'Atualizar Lista',
                  onPressed: widget.onRefreshPlaylist,
                ),
            ],
          ),
        ),

        // 2. PRÉ-VISUALIZAÇÃO DE VÍDEO NO TOPO (PARA CANAIS AO VIVO)
        if (widget.activeItem != null && widget.activeSection == MainSection.live)
          GestureDetector(
            onTap: () => _handleItemTap(widget.activeItem!, openFull: true),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.black,
                    child: widget.activeItem!.isAdult && !_adultUnlocked
                        ? const Center(
                            child: Icon(Icons.lock_rounded, color: Colors.redAccent, size: 42),
                          )
                        : widget.miniVideoWidget,
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.activeItem!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                                ),
                                if (widget.activeEpg != null)
                                  Text(
                                    widget.activeEpg!.nowTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF00E5FF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.sync_alt_rounded, color: Colors.white70, size: 18),
                            tooltip: 'Alternar TS/HLS',
                            onPressed: () => SharedStreamEngine.instance.openStream(
                              widget.activeItem!,
                              forceReload: true,
                              tryHlsFallback: true,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.fullscreen_rounded, color: Colors.black, size: 18),
                                SizedBox(width: 4),
                                Text(
                                  'Tela Cheia',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 3. BARRA DE PESQUISA
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF12151F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: widget.searchController,
              onChanged: widget.onSearchChanged,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'Pesquisar em ${widget.sectionTitle}...',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.white38, fontWeight: FontWeight.normal),
                border: InputBorder.none,
                icon: const Icon(Icons.search, color: Color(0xFF00E5FF), size: 20),
                suffixIcon: widget.searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: widget.onClearSearch,
                      )
                    : null,
              ),
            ),
          ),
        ),

        // 4. CARROSSEL HORIZONTAL DE CATEGORIAS
        SizedBox(
          height: 38,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: widget.sectionCategories.length,
            itemBuilder: (context, idx) {
              final cat = widget.sectionCategories[idx];
              final isSel = cat == widget.selectedCategory;
              final isAdultCat = _isCategoryAdult(cat);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: isAdultCat && !_adultUnlocked
                      ? const Icon(Icons.lock_rounded, size: 14, color: Colors.redAccent)
                      : null,
                  label: Text(cat),
                  selected: isSel,
                  onSelected: (_) => _handleCategoryTap(cat),
                  selectedColor: const Color(0xFF00E5FF),
                  backgroundColor: const Color(0xFF12151F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  labelStyle: TextStyle(
                    color: isSel ? Colors.black : Colors.white70,
                    fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // 5. GRADE OU LISTA DE CONTEÚDOS
        Expanded(
          child: isSeries
              ? widget.displayedSeries.isEmpty
                  ? const Center(
                      child: Text('Nenhuma série encontrada.', style: TextStyle(color: Colors.white54)),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.65,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: widget.displayedSeries.length,
                      itemBuilder: (ctx, idx) {
                        final s = widget.displayedSeries[idx];
                        final locked = s.isAdult && !_adultUnlocked;
                        return GestureDetector(
                          onTap: () => _handleSeriesTap(s),
                          child: buildStreamingPosterCard(
                            title: s.title,
                            subtitle: s.group,
                            logoUrl: s.logo,
                            badgeText: s.qualityTag,
                            isAdultLocked: locked,
                            onTap: () => _handleSeriesTap(s),
                          ),
                        );
                      },
                    )
              : isMovie
                  ? widget.displayedItems.isEmpty
                      ? const Center(
                          child: Text('Nenhum filme encontrado.', style: TextStyle(color: Colors.white54)),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.65,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: widget.displayedItems.length,
                          itemBuilder: (ctx, idx) {
                            final i = widget.displayedItems[idx];
                            final isFav = widget.favoriteIds.contains(i.id);
                            final isPlaying = widget.activeItem?.id == i.id;
                            final prog = widget.vodProgressMap[i.id];
                            final locked = i.isAdult && !_adultUnlocked;
                            return GestureDetector(
                              onTap: () => _handleItemTap(i),
                              child: buildStreamingPosterCard(
                                title: i.name,
                                subtitle: i.group,
                                logoUrl: i.logo,
                                badgeText: i.qualityTag,
                                isPlaying: isPlaying,
                                isFavorite: isFav,
                                isAdultLocked: locked,
                                progress: prog?.progress,
                                onFavoriteTap: () => widget.onToggleFavorite(i),
                                onTap: () => _handleItemTap(i),
                              ),
                            );
                          },
                        )
                  : widget.displayedItems.isEmpty
                      ? const Center(
                          child: Text('Nenhum canal encontrado.', style: TextStyle(color: Colors.white54)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: widget.displayedItems.length,
                          itemBuilder: (ctx, idx) {
                            final i = widget.displayedItems[idx];
                            final isPlaying = widget.activeItem?.id == i.id;
                            final isFav = widget.favoriteIds.contains(i.id);
                            final locked = i.isAdult && !_adultUnlocked;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isPlaying
                                    ? const Color(0xFF00E5FF).withOpacity(0.14)
                                    : const Color(0xFF12151F),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isPlaying ? const Color(0xFF00E5FF) : Colors.white10,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                onTap: () => _handleItemTap(i),
                                leading: buildChannelLogo(i.logo, size: 46, isLocked: locked),
                                title: Text(
                                  i.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isPlaying ? FontWeight.w900 : FontWeight.bold,
                                    color: isPlaying ? const Color(0xFF00E5FF) : Colors.white,
                                  ),
                                ),
                                subtitle: Text(
                                  isPlaying ? '▶ Toque novamente p/ Tela Cheia' : i.group,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isPlaying ? const Color(0xFF00E5FF) : Colors.white54,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        isFav ? Icons.star_rounded : Icons.star_border_rounded,
                                        color: isFav ? Colors.amber : Colors.white54,
                                        size: 20,
                                      ),
                                      onPressed: () => widget.onToggleFavorite(i),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.fullscreen_rounded,
                                        color: Color(0xFF00E5FF),
                                      ),
                                      onPressed: () => _handleItemTap(i, openFull: true),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
