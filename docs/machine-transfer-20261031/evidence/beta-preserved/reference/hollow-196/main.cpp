#include <nodemesh/builder.h>
#include <QVector2D>
#include <QVector3D>
#include <cmath>
#include <cstdio>
#include <map>
#include <algorithm>
int main() {
    for (float thickness : {0.0f,0.25f,0.5f,0.99f,1.0f}) {
        nodemesh::Builder builder;
        const std::vector<QVector2D> cut={{-1,-1},{1,-1},{1,1},{-1,1}};
        builder.setHollowThickness(thickness);
        builder.addNode(QVector3D(0,0,0),1,cut,0);
        builder.addNode(QVector3D(0,0,2),1,cut,0);
        builder.addEdge(0,1);
        const bool success=builder.build();
        const auto &v=builder.generatedVertices(); const auto &f=builder.generatedFaces(); const auto &src=builder.generatedVerticesSourceNodeIndices();
        size_t zeroArea=0; std::map<std::pair<size_t,size_t>,size_t> edges;
        for (const auto &face:f) {
            QVector3D n; for(size_t j=0;j<face.size();++j) { auto a=face[j],b=face[(j+1)%face.size()]; ++edges[std::minmax(a,b)]; n+=QVector3D::crossProduct(v[a],v[b]); }
            if (n.lengthSquared()<1e-12) ++zeroArea;
        }
        size_t nonmanifold=0; for(const auto &e:edges) if(e.second!=2) ++nonmanifold;
        double maxPairError=0, maxInner=0; size_t n=thickness==0?0:v.size()/2;
        for(size_t i=0;i<n;++i) { const auto origin=QVector3D(0,0,src[i]==0?0:2); auto expected=origin+(v[i]-origin)*(1-thickness); maxPairError=std::max(maxPairError,double((v[i+n]-expected).length())); maxInner=std::max(maxInner,double((v[i+n]-origin).length())); }
        std::printf("t=%.2f success=%d vertices=%zu faces=%zu zeroArea=%zu nonmanifoldEdges=%zu maxPairError=%.8g maxInnerDistance=%.8g\n",thickness,success,v.size(),f.size(),zeroArea,nonmanifold,maxPairError,maxInner);
    }
}
