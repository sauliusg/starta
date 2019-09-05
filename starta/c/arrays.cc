#include <iostream>

using std::cout;
using std::string;

class Number
{
public:
    string name;

    Number()
    {
        name = "Number";
    }
    
    Number( string name )
    {
        this->name = name;
    }
    
    virtual string get_name()
    {
        return name;
    }
};

class Integer: public Number
{
public:
    int value;

    Integer( int val ):
        Number( "Integer" )
    {
        this->value = val;
    }
    
    int get_value()
    {
        return this->value;
    }
};

int main()
{
    Number n;
    Number *an[] = { new Number, new Number, new Number };
    Integer ii = 12;
    Integer *ai[3] = { new Integer(101), new Integer(202), new Integer(33) };

    cout << "Running...\n";
    cout << n.get_name() << "\n";
    cout << an[1]->get_name() << "\n";
    cout << "========\n";

    n = ii;
    cout << n.get_name() << "\n";
    // C++ makes this assignment incompatible:
    // an = ai;
    
    cout << ai[1]->get_name() << " " << ai[1]->get_value() << "\n";

    cout << "========\n";
    Number mn[10];
    cout << mn[2].get_name() << "\n";
    Integer mi[3] = { Integer(12), Integer(13), Integer(15) };
    cout << mn[2].get_name() << "\n";
    cout << mi[2].get_name() << " " << mi[2].get_value() << "\n";

    // C++ makes this assignment incompatible:
    // mn = mi;
    
    return 0;
}
