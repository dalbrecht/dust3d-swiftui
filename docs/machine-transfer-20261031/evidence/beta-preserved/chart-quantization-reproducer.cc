#include <dust3d/uv/chart_packer.h>
#include <cstdio>
int main() {
    dust3d::ChartPacker packer;
    packer.setCharts({{123.4567f,97.1234f},{61.23456f,47.89123f}});
    const double size = packer.pack();
    const auto& charts = packer.getResult();
    const double dims[][2]={{123.4567,97.1234},{61.23456,47.89123}};
    for (size_t i=0;i<charts.size();++i) {
        const auto [x,y,w,h,flip]=charts[i];
        const double actualW=(flip ? dims[i][1] : dims[i][0])/size;
        const double actualH=(flip ? dims[i][0] : dims[i][1])/size;
        const double reportedW=flip?h:w;
        const double reportedH=flip?w:h;
        std::printf("chart %zu rotated=%d width excess=%.12g height excess=%.12g\n",i,flip,actualW-reportedW,actualH-reportedH);
    }
}
