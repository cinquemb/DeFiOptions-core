#!/usr/bin/env python3
project_name = "DefiOptions:DefiOptions-core"
"""
plot.py: plot log of % system behavior
""" % (project_name)

import matplotlib.pyplot as plt

def main():
    """
    Main function: plot the simulation.
    """
    
    # This will hold the headings for columns
    headings = []
    # This will hold each column, as a list
    columns = []

    log = open("./chain/log.tsv")
    for line in log:
        line = line.strip()
        if line == '':
            continue
        parts = line.split('\t')
        if parts[0].startswith('#'):
            # This is a header
            headings = parts
            headings[0] = headings[0][1:].strip()
        else:
            # This is data. Assume all columns are the same length
            for i, item in enumerate(parts):
                if len(columns) <= i:
                    columns.append([])
                columns[i].append(float(item))
                
    # Now plot
    
    # Find what to plot against
    x_heading = "block"
    x_column_number = headings.index(x_heading)
    if x_column_number == -1:
        raise RuntimeError("No column: " + x_heading)
        
    fig, axes = plt.subplots(len(columns)+1, 1, sharex=True)
    fig.suptitle('%s Simulation Results' % (project_name))

    axis_cursor = 0
        
    for column_number in range(len(columns)):

        try:
            if headings[column_number] == 'epoch':
                continue
            
            if column_number == x_column_number:
                # Don't plot against self
                continue
                
            # Plot this column against the designated x
            ax = axes[axis_cursor]
            ax.plot(columns[x_column_number], columns[column_number], '-')
            ax.set_xlabel(headings[x_column_number])
            ax.set_ylabel(headings[column_number])

            #print(headings[column_number])

            if 'total SB' in headings[column_number]:
                # plot diff 'total credit balance' 'total stablecoin balanace'
                axis_cursor += 1


                # Plot this column against the designated x
                ax = axes[axis_cursor]
                ncoldata = [(cB / 10**18) - (sB / 10**6) for (cB,sB) in zip(columns[column_number - 1], columns[column_number])]
                ax.plot(columns[x_column_number], ncoldata, '-')
                ax.set_xlabel(headings[x_column_number])
                ax.set_ylabel('dCB_SB')


            if 'holding' in headings[column_number]:
                # plot diff ('holding' - 'written') - (holding prev - written prev)
                axis_cursor += 1


                # Plot this column against the designated x
                ax = axes[axis_cursor]
                ncoldata = [(h - w) / 10.**18 for (h,w) in zip(columns[column_number], columns[column_number- 1])]
                ncoldata1 = []
                for nidx, x in enumerate(ncoldata):
                    if nidx > 0:
                        ncoldata1.append(x - ncoldata[nidx-1])
                    else:
                        ncoldata1.append(x)

                ax.plot(columns[x_column_number], ncoldata1, '-')
                ax.set_xlabel(headings[x_column_number])
                ax.set_ylabel('# liquidated')
            
            # Make the next plot on the next axes
            axis_cursor += 1
        except Exception as inst:
            print inst
            pass
            
    # Show all the plots
    plt.show()
    
if __name__ == "__main__":
    main()
